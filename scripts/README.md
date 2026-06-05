# RunBeam Admin Scripts

## Install

```bash
cd /Users/haneum/Desktop/Projects/goldmine/RunBeam/scripts
npm install
```

## Firestore Deploy

Uses the parent `firebase.json` and the default Firebase project `runbeam-f1f5b`.

```bash
npm run deploy:firestore
```

When `GOOGLE_APPLICATION_CREDENTIALS` or `FIREBASE_SERVICE_ACCOUNT_JSON` is set,
the deploy script uses the Firebaserules API and Firestore Admin API directly.
This bypasses the Firebase CLI `serviceusage.services.get` permission check that
can fail for narrower service accounts.

Preferred service-account auth:

```bash
export GOOGLE_APPLICATION_CREDENTIALS=/absolute/path/to/service-account.json
export FIREBASE_PROJECT_ID=runbeam-f1f5b
npm run deploy:firestore
```

If you want the original CLI path, or if you later add Firestore `fieldOverrides`,
use:

```bash
npm run deploy:firestore:cli
```

If CLI deployment fails with an authentication error, use one of these:

```bash
npx firebase-tools login
```

or CI/service-account auth:

```bash
export GOOGLE_APPLICATION_CREDENTIALS=/absolute/path/to/service-account.json
npm run deploy:firestore:cli
```

## Community Backfill

Backfills `publicUsers` search fields and migrates legacy `users/{uid}/friends` links into accepted `friendRequests`.

Preferred auth:

```bash
export GOOGLE_APPLICATION_CREDENTIALS=/absolute/path/to/service-account.json
npm run backfill:community
```

Optional project override:

```bash
export FIREBASE_PROJECT_ID=runbeam-f1f5b
```