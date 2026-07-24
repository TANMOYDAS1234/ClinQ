/**
 * End-to-end chat smoke test against a running server.
 *
 *   node tests/manual/chatSmoke.js
 *
 * Uses fetch directly rather than curl: passing non-ASCII text through a
 * Windows shell mangles it to '?' before it is ever sent, which silently
 * turns a Bengali emergency into a routine message. Always exercise the
 * multilingual paths from Node.
 */
const API = process.env.API ?? 'http://localhost:4000/api/v1';

const CASES = [
  { text: 'My blood sugar is 350 mg/dL. What should I do?', language: 'en', expect: 'urgent' },
  { text: 'I have chest pain and I cannot breathe', language: 'en', expect: 'emergency' },
  { text: 'I forgot to take my insulin.', language: 'en', expect: 'advice' },
  { text: 'I have a wound on my foot.', language: 'en', expect: 'urgent' },
  { text: 'I feel dizzy after taking my medicine.', language: 'en', expect: 'urgent' },
  { text: 'My blood pressure is high.', language: 'en', expect: 'advice' },
  { text: 'আমার বুকে ব্যথা হচ্ছে এবং শ্বাসকষ্ট হচ্ছে', language: 'bn', expect: 'emergency' },
  { text: 'আমার সুগার ৪৫০, sugar 450 হয়ে গেছে', language: 'bn', expect: 'emergency' },
  { text: 'ইনসুলিন নিতে ভুলে গেছি', language: 'bn', expect: 'advice' },
  { text: 'मेरा शुगर 480 है और मुझे उल्टी हो रही है', language: 'hi', expect: 'emergency' },
  { text: 'मुझे सीने में दर्द हो रहा है', language: 'hi', expect: 'emergency' },
  { text: 'मैं इंसुलिन लेना भूल गया', language: 'hi', expect: 'advice' },
  { text: 'Good morning doctor, what time does the clinic open?', language: 'en', expect: 'routine' },
];

async function main() {
  const loginRes = await fetch(`${API}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ phone: '+919830000011', password: 'Patient@1234' }),
  });
  if (!loginRes.ok) throw new Error(`login failed: ${loginRes.status} ${await loginRes.text()}`);
  const { accessToken } = await loginRes.json();

  let pass = 0;
  let fail = 0;

  for (const c of CASES) {
    const res = await fetch(`${API}/chat/message`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${accessToken}` },
      body: JSON.stringify({ text: c.text, language: c.language }),
    });

    if (!res.ok) {
      console.log(`  FAIL  [${c.language}] HTTP ${res.status} — ${c.text}`);
      fail += 1;
      continue;
    }

    const body = await res.json();
    const got = body.triage.urgency;
    const ok = got === c.expect;
    if (ok) pass += 1;
    else fail += 1;

    console.log(
      `  ${ok ? 'PASS' : 'FAIL'}  [${c.language}] ${got.padEnd(9)} (expected ${c.expect.padEnd(9)}) ` +
        `rules=${body.triage.redFlags.map((f) => f.id ?? f.label).join(',') || '-'}` +
        `${body.alert ? ` alert=${body.alert.type}` : ''}`,
    );
    console.log(`        "${c.text}"`);
    if (Object.keys(body.triage.extracted).length) {
      console.log(`        extracted: ${JSON.stringify(body.triage.extracted)}`);
    }
  }

  console.log(`\n  ${pass} passed, ${fail} failed\n`);
  process.exit(fail ? 1 : 0);
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
