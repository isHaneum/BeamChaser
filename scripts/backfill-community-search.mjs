#!/usr/bin/env node

import {createHash} from 'node:crypto';
import process from 'node:process';
import {applicationDefault, cert, initializeApp} from 'firebase-admin/app';
import {FieldValue, Timestamp, getFirestore} from 'firebase-admin/firestore';

const shouldApply = process.argv.includes('--apply');
const isDryRun = !shouldApply;

function normalizedSearchText(value) {
  return String(value || '').trim().toLowerCase();
}

function sanitizedUsernameBase(value) {
  return String(value || '')
    .trim()
    .split('')
    .filter(char => /[\p{L}\p{N}_]/u.test(char))
    .join('');
}

function buildUsername(userId, data = {}) {
  const candidates = [
    typeof data.username === 'string' ? data.username : null,
    typeof data.email === 'string' ? data.email.split('@')[0] : null,
    typeof data.displayName === 'string' ? data.displayName : null,
    userId,
  ];

  const suffix = normalizedSearchText(userId).slice(0, 4) || 'beam';

  for (const candidate of candidates) {
    const sanitized = sanitizedUsernameBase(candidate);
    if (!sanitized) {
      continue;
    }

    const trimmedBase = sanitized.slice(0, Math.max(3, 12 - suffix.length));
    return normalizedSearchText(`${trimmedBase}${suffix}`);
  }

  return normalizedSearchText(`runner${suffix}`);
}

function contactEmailHash(email) {
  const normalized = normalizedSearchText(email);
  if (!normalized) {
    return null;
  }

  return createHash('sha256').update(normalized).digest('hex');
}

function requestKey(senderId, receiverId) {
  return `${senderId}_${receiverId}`;
}

function friendshipKey(firstUserId, secondUserId) {
  return [firstUserId, secondUserId].sort().join('_');
}

function followKey(followerId, followingId) {
  return `${followerId}_${followingId}`;
}

function blockKey(blockerId, blockedId) {
  return `${blockerId}_${blockedId}`;
}

function chunk(items, size) {
  const result = [];
  for (let index = 0; index < items.length; index += size) {
    result.push(items.slice(index, index + size));
  }
  return result;
}

function resolveCredential() {
  if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
    return cert(JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON));
  }

  return applicationDefault();
}

function normalizeTimestamp(value, fallback = Timestamp.now()) {
  return value instanceof Timestamp ? value : fallback;
}

function toNumber(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function toInteger(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.round(parsed) : fallback;
}

async function commitWrites(db, writes, label) {
  if (writes.length === 0) {
    console.log(`${label}: 0 writes scheduled`);
    return;
  }

  if (isDryRun) {
    console.log(`[dry-run] ${label}: ${writes.length} writes scheduled`);
    for (const preview of writes.slice(0, 5)) {
      console.log(`  - ${preview.type} ${preview.ref.path}`);
    }
    return;
  }

  let committed = 0;
  for (const batchItems of chunk(writes, 400)) {
    const batch = db.batch();
    for (const item of batchItems) {
      if (item.type === 'set') {
        batch.set(item.ref, item.data, item.options || {});
      } else if (item.type === 'update') {
        batch.update(item.ref, item.data);
      } else if (item.type === 'delete') {
        batch.delete(item.ref);
      }
    }
    await batch.commit();
    committed += batchItems.length;
  }

  console.log(`${label}: ${committed} writes committed`);
}

function buildUserPatch(userId, data) {
  const now = Timestamp.now();
  const displayName = String(data.displayName || '').trim() || 'Runner';
  const createdAt = normalizeTimestamp(data.createdAt, normalizeTimestamp(data.updatedAt, now));
  const updatedAt = normalizeTimestamp(data.updatedAt, createdAt);
  const username = buildUsername(userId, data);
  const totalDistance = toNumber(data.totalDistance, toNumber(data.totalDistanceKm, 0));
  const runCount = toInteger(data.runCount, toInteger(data.totalRuns, 0));

  const patch = {};
  if (data.uid !== userId) {
    patch.uid = userId;
  }
  if (!data.username) {
    patch.username = username;
  }
  if (!data.displayName) {
    patch.displayName = displayName;
  }
  if (data.totalDistance === undefined) {
    patch.totalDistance = totalDistance;
  }
  if (data.runCount === undefined) {
    patch.runCount = runCount;
  }
  if (!(data.createdAt instanceof Timestamp)) {
    patch.createdAt = createdAt;
  }
  if (!(data.updatedAt instanceof Timestamp)) {
    patch.updatedAt = updatedAt;
  }
  if (data.photoURL === undefined) {
    patch.photoURL = null;
  }

  return {
    patch,
    normalized: {
      ...data,
      uid: userId,
      username: data.username || username,
      displayName,
      totalDistance,
      runCount,
      createdAt,
      updatedAt,
    },
  };
}

function buildPublicUserFromPrivate(userId, data) {
  const username = buildUsername(userId, data);
  const displayName = String(data.displayName || '').trim() || 'Runner';
  const updatedAt = normalizeTimestamp(data.updatedAt, Timestamp.now());
  const totalDistance = toNumber(data.totalDistance, toNumber(data.totalDistanceKm, 0));
  const runCount = toInteger(data.runCount, toInteger(data.totalRuns, 0));

  return {
    uid: userId,
    username,
    usernameLower: normalizedSearchText(username),
    displayName,
    displayNameLower: normalizedSearchText(displayName),
    searchId: normalizedSearchText(username),
    level: String(data.level || 'starter'),
    totalDistanceKm: toNumber(data.totalDistanceKm, totalDistance),
    totalDistance,
    totalRuns: toInteger(data.totalRuns, runCount),
    runCount,
    photoURL: data.photoURL || null,
    contactEmailHash: contactEmailHash(data.email) || null,
    updatedAt,
  };
}

async function backfillUsersAndPublicUsers(db) {
  const usersSnapshot = await db.collection('users').get();
  const writes = [];
  let userPatches = 0;
  let publicProfiles = 0;

  for (const document of usersSnapshot.docs) {
    const {patch, normalized} = buildUserPatch(document.id, document.data());

    if (Object.keys(patch).length > 0) {
      writes.push({
        type: 'set',
        ref: document.ref,
        data: patch,
        options: {merge: true},
      });
      userPatches += 1;
    }

    writes.push({
      type: 'set',
      ref: db.collection('publicUsers').doc(document.id),
      data: buildPublicUserFromPrivate(document.id, normalized),
      options: {merge: true},
    });
    publicProfiles += 1;
  }

  await commitWrites(db, writes, 'users/publicUsers backfill');
  console.log(`users scanned: ${usersSnapshot.size}, user patches: ${userPatches}, public profiles: ${publicProfiles}`);
}

async function migrateLegacyFriendLinks(db) {
  const usersSnapshot = await db.collection('users').select().get();
  const pairMap = new Map();

  for (const userDocument of usersSnapshot.docs) {
    const userId = userDocument.id;
    const friendsSnapshot = await db.collection('users').doc(userId).collection('friends').get();

    for (const friendDocument of friendsSnapshot.docs) {
      const friendId = friendDocument.id;
      if (!friendId || friendId === userId) {
        continue;
      }

      const dedupeKey = friendshipKey(userId, friendId);
      const friendData = friendDocument.data();
      const createdAt = normalizeTimestamp(friendData.createdAt, Timestamp.now());
      const existing = pairMap.get(dedupeKey);

      if (!existing || createdAt.toMillis() < existing.createdAt.toMillis()) {
        pairMap.set(dedupeKey, {
          senderId: userId,
          receiverId: friendId,
          createdAt,
        });
      }
    }
  }

  const writes = [];
  let migratedPairs = 0;

  for (const pair of pairMap.values()) {
    const requestId = requestKey(pair.senderId, pair.receiverId);
    const friendshipId = friendshipKey(pair.senderId, pair.receiverId);
    const createdAt = pair.createdAt;

    writes.push({
      type: 'set',
      ref: db.collection('friendRequests').doc(requestId),
      data: {
        id: requestId,
        requestId,
        senderId: pair.senderId,
        receiverId: pair.receiverId,
        fromUserId: pair.senderId,
        toUserId: pair.receiverId,
        status: 'accepted',
        source: 'legacyMigration',
        createdAt,
        updatedAt: createdAt,
        respondedAt: createdAt,
        migratedAt: FieldValue.serverTimestamp(),
      },
      options: {merge: true},
    });

    writes.push({
      type: 'set',
      ref: db.collection('friendships').doc(friendshipId),
      data: {
        id: friendshipId,
        friendshipId,
        users: [pair.senderId, pair.receiverId].sort(),
        status: 'active',
        createdAt,
        updatedAt: createdAt,
        migratedAt: FieldValue.serverTimestamp(),
      },
      options: {merge: true},
    });

    for (const [followerId, followingId] of [[pair.senderId, pair.receiverId], [pair.receiverId, pair.senderId]]) {
      const followId = followKey(followerId, followingId);
      writes.push({
        type: 'set',
        ref: db.collection('follows').doc(followId),
        data: {
          id: followId,
          followerId,
          followingId,
          isActive: true,
          createdAt,
          updatedAt: createdAt,
          migratedAt: FieldValue.serverTimestamp(),
        },
        options: {merge: true},
      });
    }

    migratedPairs += 1;
  }

  await commitWrites(db, writes, 'legacy friendships/follows migration');
  console.log(`legacy friend pairs scanned: ${pairMap.size}, migrated pairs: ${migratedPairs}`);
}

async function migrateLegacyBlocks(db) {
  const usersSnapshot = await db.collection('users').select().get();
  const writes = [];
  let migratedBlocks = 0;

  for (const userDocument of usersSnapshot.docs) {
    const blockerId = userDocument.id;
    const blockedSnapshot = await db.collection('users').doc(blockerId).collection('blockedUsers').get();

    for (const blockDocument of blockedSnapshot.docs) {
      const blockedId = blockDocument.id;
      if (!blockedId || blockedId === blockerId) {
        continue;
      }

      const blockData = blockDocument.data();
      const createdAt = normalizeTimestamp(blockData.createdAt, Timestamp.now());
      const blockId = blockKey(blockerId, blockedId);
      writes.push({
        type: 'set',
        ref: db.collection('blocks').doc(blockId),
        data: {
          id: blockId,
          blockerId,
          blockedId,
          createdAt,
          migratedAt: FieldValue.serverTimestamp(),
        },
        options: {merge: true},
      });
      migratedBlocks += 1;
    }
  }

  await commitWrites(db, writes, 'legacy blocks migration');
  console.log(`legacy block links migrated: ${migratedBlocks}`);
}

async function main() {
  initializeApp({
    credential: resolveCredential(),
    projectId: process.env.FIREBASE_PROJECT_ID || undefined,
  });

  const db = getFirestore();

  console.log(isDryRun ? 'Starting community backfill (dry-run)...' : 'Starting community backfill (--apply)...');
  if (isDryRun) {
    console.log('[dry-run] No writes will be committed. Re-run with --apply after reviewing logs and backing up production data.');
  }

  await backfillUsersAndPublicUsers(db);
  await migrateLegacyFriendLinks(db);
  await migrateLegacyBlocks(db);

  console.log(isDryRun ? 'Community backfill dry-run completed.' : 'Community backfill completed.');
}

main().catch(error => {
  console.error('Community backfill failed.');
  console.error(error);
  process.exitCode = 1;
});
