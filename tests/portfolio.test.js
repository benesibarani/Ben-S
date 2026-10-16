import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { JSDOM } from 'jsdom';

function page() {
  const html = readFileSync('dist/index.html', 'utf8');
  const script = html.match(/<script[^>]+src="([^"]+)"/)[1];
  const dom = new JSDOM(html, { url: 'http://localhost:5173', runScripts: 'outside-only' });
  dom.window.IntersectionObserver = class { observe() {} };
  dom.window.eval(readFileSync(`dist${script}`, 'utf8'));
  return dom.window.document;
}

test('renders six jobs from the supplied CV and opens the latest role', () => {
  const document = page();
  assert.equal(document.querySelectorAll('.job').length, 6);
  assert.equal(document.querySelector('.job-summary').getAttribute('aria-expanded'), 'true');
  assert.equal(document.querySelector('#job-0').hidden, false);
  assert.match(document.querySelector('.job-period').textContent, /Juni 2026/);
});

test('filters IT and sales, then restores all roles', () => {
  const document = page();
  document.querySelector('[data-filter="it"]').click();
  assert.equal(document.querySelectorAll('.job').length, 1);
  assert.match(document.querySelector('.job').textContent, /Ganesha Operation/);
  document.querySelector('[data-filter="sales"]').click();
  assert.equal(document.querySelectorAll('.job').length, 5);
  document.querySelector('[data-filter="all"]').click();
  assert.equal(document.querySelectorAll('.job').length, 6);
});

test('job details expand and collapse with correct accessibility state', () => {
  const document = page();
  const summary = document.querySelectorAll('.job-summary')[1];
  summary.click();
  assert.equal(summary.getAttribute('aria-expanded'), 'true');
  assert.equal(document.querySelector('#job-1').hidden, false);
  summary.click();
  assert.equal(document.querySelector('#job-1').hidden, true);
});

test('mobile navigation opens and closes after choosing a section', () => {
  const document = page();
  const toggle = document.querySelector('.menu-toggle');
  toggle.click();
  assert.equal(toggle.getAttribute('aria-expanded'), 'true');
  assert.ok(document.querySelector('nav').classList.contains('visible'));
  document.querySelector('nav a').click();
  assert.equal(toggle.getAttribute('aria-expanded'), 'false');
});

test('CV, portrait, and contact destinations are present', () => {
  const document = page();
  const download = document.querySelector('a[download]');
  assert.ok(existsSync(`dist${download.getAttribute('href')}`));
  assert.ok(existsSync('dist/assets/benedictus.jpeg'));
  assert.equal(document.querySelector('[href^="https://wa.me"]').getAttribute('href'), 'https://wa.me/6281260973139');
  assert.ok(document.querySelector('[href="mailto:benesibarani@gmail.com"]'));
  document.querySelectorAll('nav a').forEach(link => assert.ok(document.querySelector(link.hash)));
});
