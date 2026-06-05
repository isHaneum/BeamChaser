#!/usr/bin/env node

import {spawn} from 'node:child_process';
import {readFile} from 'node:fs/promises';
import {dirname, join} from 'node:path';
import process from 'node:process';
import {fileURLToPath} from 'node:url';
import {GoogleAuth} from 'google-auth-library';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(scriptDir, '..');
const firestoreReleaseName = 'cloud.firestore';
const firestoreDatabase = '(default)';
const authScopes = ['https://www.googleapis.com/auth/cloud-platform'];

function delay(milliseconds) {
  return new Promise(resolve => setTimeout(resolve, milliseconds));
}

async function readJson(filePath) {
  return JSON.parse(await readFile(filePath, 'utf8'));
}

async function resolveProjectId() {
  if (process.env.FIREBASE_PROJECT_ID) {
    return process.env.FIREBASE_PROJECT_ID;
  }

  const firebaseRc = await readJson(join(repoRoot, '.firebaserc'));
  const projectId = firebaseRc?.projects?.default;

  if (!projectId) {
    throw new Error('Unable to resolve Firebase project id. Set FIREBASE_PROJECT_ID or configure .firebaserc.');
  }

  return projectId;
}

function resolveAuthOptions() {
  if (process.env.FIREBASE_SERVICE_ACCOUNT_JSON) {
    return {
      credentials: JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT_JSON),
      scopes: authScopes,
    };
  }

  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    return {
      keyFile: process.env.GOOGLE_APPLICATION_CREDENTIALS,
      scopes: authScopes,
    };
  }

  return null;
}

async function getApiClient() {
  const authOptions = resolveAuthOptions();

  if (!authOptions) {
    return null;
  }

  const auth = new GoogleAuth(authOptions);
  return auth.getClient();
}

async function apiRequest(client, options) {
  const response = await client.request(options);
  return response.data;
}

function isPermissionDenied(error) {
  return error?.status === 403 || error?.code === 403 || error?.response?.status === 403;
}

function normalizeField(field) {
  return {
    fieldPath: field.fieldPath,
    order: field.order || null,
    arrayConfig: field.arrayConfig || null,
    vectorConfig: field.vectorConfig || null,
  };
}

function buildIndexSignature(index) {
  return JSON.stringify({
    queryScope: index.queryScope,
    apiScope: index.apiScope || null,
    density: index.density || null,
    fields: (index.fields || []).map(normalizeField),
  });
}

async function deployRules(client, projectId) {
  const rulesSource = await readFile(join(repoRoot, 'firestore.rules'), 'utf8');
  const ruleset = await apiRequest(client, {
    url: `https://firebaserules.googleapis.com/v1/projects/${projectId}/rulesets`,
    method: 'POST',
    data: {
      source: {
        files: [
          {
            name: 'firestore.rules',
            content: rulesSource,
          },
        ],
      },
    },
  });

  const release = await apiRequest(client, {
    url: `https://firebaserules.googleapis.com/v1/projects/${projectId}/releases/${firestoreReleaseName}`,
    method: 'PATCH',
    data: {
      release: {
        name: `projects/${projectId}/releases/${firestoreReleaseName}`,
        rulesetName: ruleset.name,
      },
      updateMask: 'ruleset_name',
    },
  });

  console.log(`Firestore rules deployed via Rules API: ${release.rulesetName}`);
}

async function listIndexes(client, projectId, collectionGroup) {
  const indexes = [];
  let pageToken = null;

  do {
    const url = new URL(
      `https://firestore.googleapis.com/v1/projects/${projectId}/databases/${firestoreDatabase}/collectionGroups/${encodeURIComponent(collectionGroup)}/indexes`
    );

    if (pageToken) {
      url.searchParams.set('pageToken', pageToken);
    }

    const response = await apiRequest(client, {
      url: url.toString(),
      method: 'GET',
    });

    indexes.push(...(response.indexes || []));
    pageToken = response.nextPageToken || null;
  } while (pageToken);

  return indexes;
}

async function createIndex(client, projectId, index) {
  return apiRequest(client, {
    url: `https://firestore.googleapis.com/v1/projects/${projectId}/databases/${firestoreDatabase}/collectionGroups/${encodeURIComponent(index.collectionGroup)}/indexes`,
    method: 'POST',
    data: {
      queryScope: index.queryScope,
      fields: index.fields,
    },
  });
}

async function waitForOperations(client, operations) {
  if (operations.length === 0) {
    return;
  }

  const pending = new Map(operations.map(operation => [operation.name, operation]));
  const deadline = Date.now() + 5 * 60 * 1000;

  while (pending.size > 0) {
    for (const [operationName, operation] of pending) {
      const result = await apiRequest(client, {
        url: `https://firestore.googleapis.com/v1/${operationName}`,
        method: 'GET',
      });

      if (!result.done) {
        continue;
      }

      if (result.error) {
        throw new Error(`Index creation failed for ${operation.collectionGroup}: ${result.error.message || JSON.stringify(result.error)}`);
      }

      pending.delete(operationName);
      console.log(`Firestore index ready: ${operation.collectionGroup} ${operation.summary}`);
    }

    if (pending.size === 0) {
      break;
    }

    if (Date.now() >= deadline) {
      console.log(`Firestore index creation is still in progress for ${pending.size} operation(s).`);
      for (const operation of pending.values()) {
        console.log(`Pending operation: ${operation.name}`);
      }
      return;
    }

    await delay(2000);
  }
}

async function deployIndexes(client, projectId) {
  const indexesConfig = await readJson(join(repoRoot, 'firestore.indexes.json'));
  const fieldOverrides = indexesConfig.fieldOverrides || [];

  if (fieldOverrides.length > 0) {
    throw new Error('Direct service-account deploy does not support Firestore fieldOverrides yet. Use deploy:firestore:cli for that configuration.');
  }

  const collectionGroups = [...new Set((indexesConfig.indexes || []).map(index => index.collectionGroup))];
  const existingByCollectionGroup = new Map();

  for (const collectionGroup of collectionGroups) {
    const indexes = await listIndexes(client, projectId, collectionGroup);
    existingByCollectionGroup.set(
      collectionGroup,
      new Set(indexes.map(buildIndexSignature))
    );
  }

  const operations = [];

  for (const index of indexesConfig.indexes || []) {
    const existing = existingByCollectionGroup.get(index.collectionGroup);
    const signature = buildIndexSignature(index);

    if (existing?.has(signature)) {
      console.log(`Firestore index already present: ${index.collectionGroup} ${signature}`);
      continue;
    }

    const operation = await createIndex(client, projectId, index);
    console.log(`Firestore index creation started: ${index.collectionGroup} ${signature}`);
    operations.push({
      name: operation.name,
      collectionGroup: index.collectionGroup,
      summary: signature,
    });
    existing?.add(signature);
  }

  await waitForOperations(client, operations);
}

async function runFirebaseCli(projectId, reason = 'No service-account environment found. Falling back to firebase-tools CLI deploy.') {
  console.log(reason);

  await new Promise((resolve, reject) => {
    const child = spawn(
      'npx',
      [
        'firebase-tools',
        '--config',
        '../firebase.json',
        '--project',
        projectId,
        'deploy',
        '--only',
        'firestore:rules,firestore:indexes',
      ],
      {
        cwd: scriptDir,
        stdio: 'inherit',
      }
    );

    child.on('exit', code => {
      if (code === 0) {
        resolve();
        return;
      }

      reject(new Error(`firebase-tools exited with code ${code}`));
    });
    child.on('error', reject);
  });
}

async function main() {
  const projectId = await resolveProjectId();
  const client = await getApiClient();

  if (!client) {
    await runFirebaseCli(projectId);
    return;
  }

  console.log(`Deploying Firestore config with service-account API access for project ${projectId}...`);
  await deployRules(client, projectId);
  try {
    await deployIndexes(client, projectId);
  } catch (error) {
    if (!isPermissionDenied(error)) {
      throw error;
    }

    await runFirebaseCli(
      projectId,
      'Service account cannot create Firestore indexes directly. Falling back to firebase-tools CLI for index deployment.'
    );
    console.log('Firestore config deploy completed.');
    return;
  }

  console.log('Firestore config deploy completed.');
}

main().catch(error => {
  console.error('Firestore config deploy failed.');
  console.error(error);
  process.exitCode = 1;
});