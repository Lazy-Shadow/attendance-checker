const admin = require('firebase-admin');
const readline = require('readline');

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

rl.question('Enter the path to your service account JSON file (or press Enter to use application default): ', async (keyFilename) => {
  rl.close();

  if (keyFilename && keyFilename.trim() !== '') {
    admin.initializeApp({
      credential: admin.credential.cert(keyFilename.trim())
    });
  } else {
    try {
      admin.initializeApp({
        projectId: 'attendance-checker-9f22b'
      });
    } catch (e) {
      console.log('No project specified, using GOOGLE_APPLICATION_CREDENTIALS...');
      process.exit(1);
    }
  }

  const db = admin.firestore();
  const sourceCollection = 'attendance_days';
  const targetCollection = 'attendance_events';

  console.log(`\nStarting migration: ${sourceCollection} -> ${targetCollection}`);
  console.log('Fetching documents from source collection...\n');

  async function migrateCollection() {
    try {
      const sourceSnapshot = await db.collection(sourceCollection).get();
      
      if (sourceSnapshot.empty) {
        console.log('No documents found in source collection.');
        return;
      }

      const totalDocs = sourceSnapshot.size;
      console.log(`Found ${totalDocs} documents to migrate.\n`);

      let copiedCount = 0;

      // Copy documents in batches
      for (let i = 0; i < sourceSnapshot.docs.length; i += 500) {
        const batch = db.batch();
        const batchDocs = sourceSnapshot.docs.slice(i, i + 500);

        for (const doc of batchDocs) {
          const newDocRef = db.collection(targetCollection).doc(doc.id);
          batch.set(newDocRef, doc.data());
        }

        await batch.commit();
        copiedCount += batchDocs.length;
        console.log(`Copied ${copiedCount}/${totalDocs} documents...`);
      }

      console.log(`\n✅ Copied ${totalDocs} documents to ${targetCollection}.\n`);

      // Delete source documents in batches
      console.log('Deleting documents from source collection...\n');

      let deletedCount = 0;
      let hasMore = true;

      while (hasMore) {
        const remainingSnapshot = await db.collection(sourceCollection).get();
        
        if (remainingSnapshot.empty) {
          hasMore = false;
          break;
        }

        const batch = db.batch();
        const batchDocs = remainingSnapshot.docs.slice(0, 500);

        for (const doc of batchDocs) {
          batch.delete(doc.ref);
        }

        await batch.commit();
        deletedCount += batchDocs.length;
        console.log(`Deleted ${deletedCount}/${totalDocs} documents...`);
      }

      console.log(`\n✅ Migration complete!`);
      console.log(`   - Copied: ${totalDocs} documents to ${targetCollection}`);
      console.log(`   - Deleted: ${deletedCount} documents from ${sourceCollection}`);
      console.log(`\n⚠️  Note: Check Firebase Console to verify the migration was successful.`);

    } catch (error) {
      console.error('\n❌ Migration failed:', error.message);
      process.exit(1);
    }
  }

  migrateCollection();
});
