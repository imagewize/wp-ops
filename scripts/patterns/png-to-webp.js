#!/usr/bin/env node

/**
 * Convert PNG screenshots to WebP
 *
 * Converts a single PNG or a whole directory of pattern-*.png files to
 * optimized WebP using sharp.
 *
 * Usage:
 *   node png-to-webp.js <input-file> [options]
 *   node png-to-webp.js --all --dir=<screenshots-dir> [options]
 *
 * Options:
 *   --all                  Convert every pattern-*.png file in --dir
 *   --dir=<path>           Source directory for --all (default: ./screenshots)
 *   --output-dir=<path>    Output directory (default: same as source file/dir)
 *   --quality=85           WebP quality 1-100 (default: 85)
 *   --dry-run              Show what would be done without writing files
 *
 * Examples:
 *   node png-to-webp.js pattern-hero-dark.png
 *   node png-to-webp.js --all --dir=./screenshots --output-dir=./webp
 *   node png-to-webp.js --all --dir=./screenshots --quality=90
 *
 * @desc     Convert PNG pattern screenshots to WebP using sharp
 * @category content
 * @platform any
 * @runs     local
 * @requires node
 * @arg      input-file     optional  {pattern-hero-dark.png}  Single PNG to convert (omit when using --all)
 * @flag     --all          optional  {}  Convert every pattern-*.png file in --dir
 * @flag     --dir          optional  {./screenshots}  Source directory for --all
 * @flag     --output-dir   optional  {./webp}  Output directory (default: same as source)
 * @flag     --quality      optional  {85}  WebP quality 1-100
 * @flag     --dry-run      optional  {}  Show what would be done without writing files
 * @example  wp-ops png-to-webp --all --dir=./screenshots --quality=90
 * @doc      scripts/patterns/README.md
 */

const sharp = require('sharp');
const fs = require('fs');
const path = require('path');

const DEFAULT_QUALITY = 85;
const INPUT_PATTERN = /^pattern-.*\.png$/;

const colors = {
  reset: '\x1b[0m',
  green: '\x1b[32m',
  blue: '\x1b[34m',
  yellow: '\x1b[33m',
  red: '\x1b[31m',
  cyan: '\x1b[36m',
  magenta: '\x1b[35m'
};

function log(message, color = 'reset') {
  console.log(`${colors[color]}${message}${colors.reset}`);
}

function parseArgs(argv) {
  const flag = (name) => argv.find((a) => a.startsWith(`--${name}=`))?.split('=').slice(1).join('=');

  const inputFile = argv.find((a) => !a.startsWith('--'));
  const convertAll = argv.includes('--all');
  const dryRun = argv.includes('--dry-run');
  const dir = path.resolve(flag('dir') || './screenshots');
  const quality = parseInt(flag('quality') || String(DEFAULT_QUALITY), 10);
  const outputDirArg = flag('output-dir');

  if (!inputFile && !convertAll) {
    log('Error: specify an input file or use --all --dir=<path>', 'red');
    process.exit(1);
  }

  if (quality < 1 || quality > 100) {
    log('Error: quality must be between 1-100', 'red');
    process.exit(1);
  }

  return { inputFile, convertAll, dir, quality, outputDirArg, dryRun };
}

function getInputFiles(opts) {
  if (opts.convertAll) {
    if (!fs.existsSync(opts.dir)) {
      log(`Error: directory not found: ${opts.dir}`, 'red');
      process.exit(1);
    }
    const files = fs
      .readdirSync(opts.dir)
      .filter((f) => INPUT_PATTERN.test(f))
      .map((f) => path.join(opts.dir, f));

    if (files.length === 0) {
      log(`No pattern-*.png files found in ${opts.dir}`, 'yellow');
    }
    return files;
  }

  const inputPath = path.resolve(opts.inputFile);
  if (!fs.existsSync(inputPath)) {
    log(`Error: input file not found: ${inputPath}`, 'red');
    process.exit(1);
  }
  return [inputPath];
}

async function convertToWebP(inputPath, outputPath, quality, dryRun) {
  if (dryRun) {
    log(`[DRY RUN] Would convert: ${path.basename(inputPath)} -> ${path.basename(outputPath)}`, 'yellow');
    return null;
  }

  const inputSize = fs.statSync(inputPath).size;
  log(`Converting: ${path.basename(inputPath)} (${Math.round(inputSize / 1024)}KB)`, 'cyan');

  await sharp(inputPath).webp({ quality }).toFile(outputPath);

  const outputSize = fs.statSync(outputPath).size;
  const reduction = Math.round(((inputSize - outputSize) / inputSize) * 100);
  log(`Created: ${path.basename(outputPath)} (${Math.round(outputSize / 1024)}KB, ${reduction}% smaller)`, 'green');

  return { inputSize, outputSize };
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));

  log('\nWebP Conversion', 'magenta');
  log(`Quality: ${opts.quality}%  |  dry-run: ${opts.dryRun}`, 'blue');

  const inputFiles = getInputFiles(opts);
  if (inputFiles.length === 0) {
    process.exit(0);
  }

  log(`Found ${inputFiles.length} file(s) to convert\n`, 'blue');

  const results = [];
  for (const inputPath of inputFiles) {
    const outputDir = opts.outputDirArg ? path.resolve(opts.outputDirArg) : path.dirname(inputPath);
    if (!opts.dryRun && !fs.existsSync(outputDir)) {
      fs.mkdirSync(outputDir, { recursive: true });
    }
    const outputPath = path.join(outputDir, `${path.basename(inputPath, '.png')}.webp`);

    try {
      const result = await convertToWebP(inputPath, outputPath, opts.quality, opts.dryRun);
      if (result) results.push(result);
    } catch (error) {
      log(`Skipping ${path.basename(inputPath)}: ${error.message}`, 'red');
    }
  }

  if (!opts.dryRun && results.length > 0) {
    const totalIn = results.reduce((sum, r) => sum + r.inputSize, 0);
    const totalOut = results.reduce((sum, r) => sum + r.outputSize, 0);
    log(`\nConverted ${results.length} file(s), ${Math.round(((totalIn - totalOut) / totalIn) * 100)}% smaller overall`, 'green');
  }
}

main().catch((error) => {
  log(`\nFatal error: ${error.message}`, 'red');
  console.error(error);
  process.exit(1);
});
