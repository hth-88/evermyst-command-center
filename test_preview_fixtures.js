import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const fixturesPath = path.join(__dirname, 'src/scoring/fixtures.json');
const fixtures = JSON.parse(fs.readFileSync(fixturesPath, 'utf8'));

// Import compiled preview function or dynamic import
// Since vite build produces dist or we can import src/scoring/preview.ts with experimental strip types
import { previewPoints } from './src/scoring/preview.ts';

console.log('--- BẮT ĐẦU TEST FIXTURES SCORING ---');
let passed = 0;
let failed = 0;

for (const tc of fixtures.test_cases) {
  const result = previewPoints(
    tc.scoring_type,
    tc.scoring_config,
    tc.input,
    tc.min_score,
    tc.max_score
  );

  const pointsMatch = result.points === tc.expected_points;
  const validMatch = result.isValid === tc.is_valid;

  if (pointsMatch && validMatch) {
    console.log(`[PASS] Case ${tc.id}: ${tc.scoring_type} => points=${result.points}, isValid=${result.isValid}`);
    passed++;
  } else {
    console.error(`[FAIL] Case ${tc.id}:`);
    console.error(`  Expected points: ${tc.expected_points}, got: ${result.points}`);
    console.error(`  Expected isValid: ${tc.is_valid}, got: ${result.isValid}`);
    console.error(`  Error message: ${result.error}`);
    failed++;
  }
}

console.log(`\nKẾT QUẢ: ${passed} passed, ${failed} failed`);
if (failed > 0) process.exit(1);
