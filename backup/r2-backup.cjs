#!/usr/bin/env node
'use strict';

// Remote backup helper for export.sh. Talks to R2/S3 with the AWS SDK the app
// already has (it comes with @strapi/provider-upload-aws-s3), so servers need
// nothing installed: Cloudways app users can't install software outside
// public_html.
//
// Run from the app directory, credentials come from the environment:
//   node r2-backup.cjs check [media]           can we reach the bucket(s)?
//   node r2-backup.cjs upload <file> <key>     upload, then verify size + md5
//   node r2-backup.cjs copy-media <app>        copy the media bucket to <app>/media/
//                                              (new versions to <app>/media-versions/)
//   node r2-backup.cjs link <key> <seconds>    presigned download URL
//
// Backup bucket: BACKUP_R2_ENDPOINT, BACKUP_R2_ACCESS_KEY_ID,
//                BACKUP_R2_SECRET_ACCESS_KEY, BACKUP_R2_BUCKET
// Media bucket:  MEDIA_S3_ENDPOINT (empty = AWS), MEDIA_S3_REGION,
//                MEDIA_S3_ACCESS_KEY_ID, MEDIA_S3_SECRET_ACCESS_KEY, MEDIA_S3_BUCKET

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const PART_SIZE = 64 * 1024 * 1024;
const COPY_CONCURRENCY = 8;
const COPY_ATTEMPTS = 3;
const PROGRESS_EVERY_MS = 30 * 1000;

function fail(message) {
  console.error(message);
  process.exit(1);
}

function env(name) {
  const value = process.env[name];
  if (!value) fail(`${name} is not set`);
  return value;
}

// From the app's node_modules: hoisted, or nested under the upload provider
function loadSdk(name) {
  const bases = [process.cwd()];
  try {
    bases.push(path.dirname(require.resolve('@strapi/provider-upload-aws-s3/package.json', { paths: [process.cwd()] })));
  } catch {
    // provider not installed, only the app root is left to try
  }
  for (const base of bases) {
    try {
      return require(require.resolve(name, { paths: [base] }));
    } catch {
      // try the next base
    }
  }
  fail(`${name} not found in this app's node_modules (it comes with @strapi/provider-upload-aws-s3). Run from the app directory, after npm install.`);
}

const {
  S3Client,
  ListObjectsV2Command,
  HeadObjectCommand,
  GetObjectCommand,
} = loadSdk('@aws-sdk/client-s3');
const { Upload } = loadSdk('@aws-sdk/lib-storage');

function client(prefix) {
  const endpoint = process.env[`${prefix}_ENDPOINT`] || undefined;
  return new S3Client({
    region: process.env[`${prefix}_REGION`] || 'auto',
    endpoint,
    // R2 and other S3-compatible services accept path style, AWS wants virtual hosts
    forcePathStyle: Boolean(endpoint),
    credentials: {
      accessKeyId: env(`${prefix}_ACCESS_KEY_ID`),
      secretAccessKey: env(`${prefix}_SECRET_ACCESS_KEY`),
    },
  });
}

function backupBucket() {
  return { s3: client('BACKUP_R2'), bucket: env('BACKUP_R2_BUCKET') };
}

function mediaBucket() {
  return { s3: client('MEDIA_S3'), bucket: env('MEDIA_S3_BUCKET') };
}

function describe(error) {
  return error.name && error.name !== 'Error' ? `${error.name}: ${error.message}` : error.message;
}

function md5File(file) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash('md5');
    fs.createReadStream(file)
      .on('error', reject)
      .on('data', (chunk) => hash.update(chunk))
      .on('end', () => resolve(hash.digest('hex')));
  });
}

async function listAll({ s3, bucket }, prefix) {
  const objects = new Map();
  let token;
  do {
    const page = await s3.send(new ListObjectsV2Command({ Bucket: bucket, Prefix: prefix, ContinuationToken: token }));
    for (const object of page.Contents || []) {
      objects.set(object.Key.slice(prefix.length), object);
    }
    token = page.IsTruncated ? page.NextContinuationToken : undefined;
  } while (token);
  return objects;
}

async function check(which) {
  const targets = [['backup', backupBucket()]];
  if (which === 'media') targets.push(['media', mediaBucket()]);
  for (const [label, { s3, bucket }] of targets) {
    try {
      await s3.send(new ListObjectsV2Command({ Bucket: bucket, MaxKeys: 1 }));
    } catch (error) {
      fail(`Cannot access the ${label} bucket ${bucket}: ${describe(error)}`);
    }
  }
}

async function upload(file, key) {
  const { s3, bucket } = backupBucket();
  const size = fs.statSync(file).size;
  const md5 = await md5File(file);

  await new Upload({
    client: s3,
    params: { Bucket: bucket, Key: key, Body: fs.createReadStream(file), Metadata: { md5 } },
    partSize: PART_SIZE,
    queueSize: 4,
  }).done();

  const head = await s3.send(new HeadObjectCommand({ Bucket: bucket, Key: key }));
  if (head.ContentLength !== size) {
    fail(`Uploaded size ${head.ContentLength} does not match the local file (${size} bytes)`);
  }
  // A single-part upload's ETag is the md5 of the content. A multipart one
  // (over PART_SIZE) isn't, so those rely on the size and the SDK's checksums.
  const etag = (head.ETag || '').replace(/"/g, '');
  if (!etag.includes('-')) {
    if (etag !== md5) fail(`Uploaded md5 ${etag} does not match the local file (${md5})`);
    console.log(`md5 ${md5}`);
  } else {
    console.log(`size ${size} bytes (multipart upload)`);
  }
}

async function copyOne(media, backup, key, destKey) {
  for (let attempt = 1; ; attempt += 1) {
    try {
      const object = await media.s3.send(new GetObjectCommand({ Bucket: media.bucket, Key: key }));
      await new Upload({
        client: backup.s3,
        params: { Bucket: backup.bucket, Key: destKey, Body: object.Body, ContentType: object.ContentType },
        partSize: PART_SIZE,
        queueSize: 2,
      }).done();
      return;
    } catch (error) {
      if (attempt >= COPY_ATTEMPTS) throw error;
    }
  }
}

// The backup never overwrites or deletes an object, so it works under an R2
// bucket lock and keeps every version of a file:
//   <app>/media/<key>                     first copy of each file
//   <app>/media-versions/<stamp>/<key>    a file replaced in the media library
//                                         (Strapi's "replace media" keeps the key),
//                                         as copied by the run at <stamp>
// The newest copy of a file is its latest media-versions entry, else media/.
async function copyMedia(app) {
  const media = mediaBucket();
  const backup = backupBucket();
  const base = `${app.replace(/\/+$/, '')}/`;
  // Sorts in time order, unique per run
  const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d+Z$/, 'Z');

  const [source, firstCopies, versions] = await Promise.all([
    listAll(media, ''),
    listAll(backup, `${base}media/`),
    listAll(backup, `${base}media-versions/`),
  ]);
  const newest = new Map(firstCopies);
  for (const [stampedKey, object] of [...versions].sort(([a], [b]) => a.localeCompare(b))) {
    newest.set(stampedKey.slice(stampedKey.indexOf('/') + 1), object);
  }

  // New files go to media/; files that differ from their newest copy (size, or
  // modified after it was copied) get a new version
  const todo = [];
  for (const [key, object] of source) {
    if (key.endsWith('/')) continue;
    const copy = newest.get(key);
    if (!copy) {
      todo.push([key, object, `${base}media/${key}`]);
    } else if (copy.Size !== object.Size || object.LastModified > copy.LastModified) {
      todo.push([key, object, `${base}media-versions/${stamp}/${key}`]);
    }
  }
  const bytes = todo.reduce((sum, [, object]) => sum + (object.Size || 0), 0);
  const changed = todo.filter(([, , destKey]) => destKey.includes('/media-versions/')).length;
  console.log(`${source.size} files in ${media.bucket}, ${todo.length - changed} new and ${changed} replaced to copy (${(bytes / 1048576).toFixed(1)} MB)`);

  let done = 0;
  const failed = [];
  let lastReport = Date.now();
  const queue = [...todo];
  async function worker() {
    for (let next = queue.shift(); next; next = queue.shift()) {
      const [key, , destKey] = next;
      try {
        await copyOne(media, backup, key, destKey);
      } catch (error) {
        failed.push(`${key}: ${describe(error)}`);
      }
      done += 1;
      if (Date.now() - lastReport >= PROGRESS_EVERY_MS) {
        lastReport = Date.now();
        console.log(`  ${done} / ${todo.length} copied`);
      }
    }
  }
  await Promise.all(Array.from({ length: COPY_CONCURRENCY }, worker));

  if (failed.length) {
    console.error(`${failed.length} file(s) could not be copied:`);
    failed.slice(0, 20).forEach((line) => console.error(`  ${line}`));
    if (failed.length > 20) console.error(`  ... and ${failed.length - 20} more`);
    process.exit(1);
  }
  console.log(`${todo.length} copied, ${source.size - todo.length} already in the backup`);
}

async function link(key, seconds) {
  const { getSignedUrl } = loadSdk('@aws-sdk/s3-request-presigner');
  const { s3, bucket } = backupBucket();
  console.log(await getSignedUrl(s3, new GetObjectCommand({ Bucket: bucket, Key: key }), { expiresIn: Number(seconds) }));
}

const [command, ...args] = process.argv.slice(2);
const commands = {
  check: () => check(args[0]),
  upload: () => upload(args[0], args[1]),
  'copy-media': () => copyMedia(args[0]),
  link: () => link(args[0], args[1]),
};
if (!commands[command]) fail(`Unknown command: ${command || '(none)'}. Use check, upload, copy-media or link.`);
commands[command]().catch((error) => fail(describe(error)));
