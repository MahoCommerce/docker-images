// Drives the Maho web installation wizard against a running container.
//
// A browser is needed, not form posts: the Continue button ships disabled until
// installer.js enables it, and the database step disables the inputs of every
// engine form that is not selected.
//
// Usage: node web-install.js <base-url> <artifact-dir>

const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const BASE = process.argv[2] || 'http://localhost:8080';
const ARTIFACTS = process.argv[3] || 'test-artifacts';

// sqlite needs no database service. mysql drives a different form.
const DB_ENGINE = process.env.DB_ENGINE || 'sqlite';
const DB = {
    host: process.env.DB_HOST || 'mysql',
    name: process.env.DB_NAME || 'maho',
    user: process.env.DB_USER || 'maho',
    pass: process.env.DB_PASS || 'maho',
};

const STEP_TIMEOUT = 60 * 1000;
const INSTALL_TIMEOUT = 10 * 60 * 1000;   // the schema install runs in one request

const ADMIN = {
    firstname: 'Test',
    lastname: 'Admin',
    email: 'admin@example.com',
    username: 'admin',
    password: 'TestAdmin123!secure',
};

const consoleErrors = [];
const badResponses = [];

// These errors never resolve, so waiting for a selector would burn the whole
// install timeout. Stop as soon as one happens.
const FATAL_NET_ERRORS = [
    'net::ERR_TOO_MANY_REDIRECTS',
    'net::ERR_CONNECTION_RESET',
    'net::ERR_EMPTY_RESPONSE',
];
let failFast;
const fatalPromise = new Promise((_, reject) => { failFast = reject; });
const orFatal = (promise) => Promise.race([promise, fatalPromise]);

const log = (msg) => console.log(`  ${msg}`);

async function capture(page, name) {
    fs.mkdirSync(ARTIFACTS, { recursive: true });
    await page.screenshot({ path: path.join(ARTIFACTS, `${name}.png`), fullPage: true }).catch(() => {});
    fs.writeFileSync(path.join(ARTIFACTS, `${name}.html`), await page.content().catch(() => ''));
}

const submitStep = (page) => page.click('#form-validate button[type="submit"]');

(async () => {
    const browser = await chromium.launch();
    const page = await browser.newPage();
    page.setDefaultTimeout(STEP_TIMEOUT);

    page.on('console', (m) => {
        if (m.type() === 'error') consoleErrors.push(m.text());
    });
    // A script or stylesheet that fails to load leaves the wizard looking fine
    // but unusable. This is what a browser adds over a status code.
    page.on('response', (r) => {
        if (r.status() >= 400 && r.url().startsWith(BASE)) badResponses.push(`${r.status()} ${r.url()}`);
    });
    // A reset connection returns no response, so catch it here instead.
    page.on('requestfailed', (r) => {
        const err = r.failure()?.errorText || 'failed';
        badResponses.push(`${err} ${r.url()}`);
        if (FATAL_NET_ERRORS.includes(err)) failFast(new Error(`${err} on ${r.url()}`));
    });

    try {
        log('opening the store, which must redirect to the wizard');
        await page.goto(`${BASE}/`, { waitUntil: 'domcontentloaded' });
        await orFatal(page.waitForSelector('#licenseForm'));
        if (!page.url().includes('/install')) {
            throw new Error(`expected a redirect to /install, landed on ${page.url()}`);
        }

        log('license: accepting the terms');
        // The button stays disabled until installer.js sees this change event,
        // so this also proves the module script loaded and ran.
        await page.check('#agree');
        await page.waitForSelector('#submitButton:not([disabled])', { timeout: 10000 });
        await page.click('#submitButton');

        log('localization: keeping the defaults');
        await page.waitForSelector('#form-validate');
        // Do not touch #locale: changing it reloads the step. Language packs
        // download from the network, so leave them off.
        for (const name of ['localization[install_langpack]', 'localization[import_regions]']) {
            const box = page.locator(`input[name="${name}"]`);
            if (await box.count() > 0) await box.uncheck();
        }
        await submitStep(page);

        log(`configuration: selecting ${DB_ENGINE}`);
        await page.waitForSelector('#db_engine_select');
        // selectOption fires the change event, which shows the chosen engine
        // form and enables its inputs. Without it they all stay disabled.
        await page.selectOption('#db_engine_select', DB_ENGINE);
        if (DB_ENGINE === 'mysql') {
            await page.waitForSelector('#mysql_host:not([disabled])');
            await page.fill('#mysql_host', DB.host);
            await page.fill('#mysql_dbname', DB.name);
            await page.fill('#mysql_user', DB.user);
            await page.fill('#mysql_password', DB.pass);
        } else {
            await page.waitForSelector('#sqlite_db_path:not([disabled])');
        }
        await submitStep(page);

        // Steps: license, locale, configuration, sampledata, administrator,
        // complete. Submitting configuration installs the schema.
        log('installing the database schema, this takes a while');
        await orFatal(page.waitForSelector('#skip-btn, #firstname', { timeout: INSTALL_TIMEOUT }));

        if (await page.locator('#skip-btn').count() > 0) {
            log('sample data: skipping');   // it tests the importer, not the image
            await page.click('#skip-btn');
            await orFatal(page.waitForSelector('#firstname', { timeout: INSTALL_TIMEOUT }));
        }

        log('administrator: creating the account');
        await page.fill('#firstname', ADMIN.firstname);
        await page.fill('#lastname', ADMIN.lastname);
        await page.fill('#email_address', ADMIN.email);
        await page.fill('#username', ADMIN.username);
        await page.fill('#password', ADMIN.password);
        await page.fill('#confirmation', ADMIN.password);
        await submitStep(page);

        log('waiting for the wizard to report success');
        await orFatal(page.waitForURL(/\/install\/wizard\/complete/, { timeout: INSTALL_TIMEOUT }));
        await page.waitForSelector('.installation-complete');
        if (!/all set/i.test(await page.textContent('body'))) {
            throw new Error('the final page does not report a successful installation');
        }
        await capture(page, 'installed');

        // The pages can move forward while the wizard still reports a problem.
        const errors = await page.locator('.error-msg').allTextContents();
        if (errors.length > 0) throw new Error(`the wizard reported errors: ${errors.join(' | ')}`);
    } catch (err) {
        await capture(page, 'failure');
        console.error(`\n  FAILED: ${err.message}`);
        console.error(`  last url: ${page.url()}`);
        if (consoleErrors.length) console.error(`  console errors:\n    ${consoleErrors.join('\n    ')}`);
        if (badResponses.length) console.error(`  failed requests:\n    ${badResponses.join('\n    ')}`);
        await browser.close();
        process.exit(1);
    }

    await browser.close();

    if (badResponses.length > 0) {
        console.error(`\n  FAILED: the wizard requested things that did not load:`);
        console.error(`    ${badResponses.join('\n    ')}`);
        process.exit(1);
    }
    // Not fatal: the wizard is upstream code and a console error does not
    // always break it.
    if (consoleErrors.length > 0) {
        console.warn(`  note: ${consoleErrors.length} console error(s):`);
        console.warn(`    ${consoleErrors.join('\n    ')}`);
    }

    console.log(`  admin user: ${ADMIN.username} / ${ADMIN.password}`);
})();
