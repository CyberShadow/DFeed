import { test, expect } from "@playwright/test";

test.describe("Posting", () => {
  test("can create a new thread in local group", async ({ page }) => {
    // Generate unique identifiers for this test
    const timestamp = Date.now();
    const testSubject = `Test Thread ${timestamp}`;
    const testBody = `This is a test message body created at ${timestamp}`;
    const testName = "Test User";
    const testEmail = "test@example.com";

    // Navigate to the test group
    await page.goto("/group/test");
    await expect(page.locator("body")).toBeVisible();

    // Click "Create thread" button
    await page.click(
      'input[value="Create thread"], input[alt="Create thread"]'
    );

    // Wait for the new post form
    await expect(page.locator("#postform")).toBeVisible();

    // Fill in the form
    await page.fill("#postform-name", testName);
    await page.fill("#postform-email", testEmail);
    await page.fill("#postform-subject", testSubject);
    await page.fill("#postform-text", testBody);

    // Submit the form
    await page.click('input[name="action-send"]');

    // Wait for redirect to the posted thread
    await expect(page).toHaveURL(/\/(thread|post)\//);

    // Verify the post content is visible
    await expect(page.locator("body")).toContainText(testSubject);
    await expect(page.locator("body")).toContainText(testBody);
  });

  test("thread appears in group listing after posting", async ({ page }) => {
    // Generate unique identifiers for this test
    const timestamp = Date.now();
    const testSubject = `Listing Test ${timestamp}`;
    const testBody = `Message for listing test ${timestamp}`;

    // Create a new thread
    await page.goto("/newpost/test");
    await page.fill("#postform-name", "Test User");
    await page.fill("#postform-email", "test@example.com");
    await page.fill("#postform-subject", testSubject);
    await page.fill("#postform-text", testBody);
    await page.click('input[name="action-send"]');

    // Wait for posting to complete
    await expect(page).toHaveURL(/\/(thread|post)\//);

    // Navigate to group listing
    await page.goto("/group/test");

    // Verify the new thread appears in the listing
    await expect(page.locator("body")).toContainText(testSubject);
  });

  test("posting form renders correctly", async ({ page }) => {
    // Navigate to new post form
    await page.goto("/newpost/test");

    // Verify form elements are present
    await expect(page.locator("#postform")).toBeVisible();
    await expect(page.locator("#postform-name")).toBeVisible();
    await expect(page.locator("#postform-email")).toBeVisible();
    await expect(page.locator("#postform-subject")).toBeVisible();
    await expect(page.locator("#postform-text")).toBeVisible();
    await expect(page.locator('input[name="action-send"]')).toBeVisible();
    await expect(page.locator('input[name="action-save"]')).toBeVisible();
  });

  test("can preview post before sending", async ({ page }) => {
    const timestamp = Date.now();
    const testSubject = `Preview Test ${timestamp}`;
    const testBody = `Preview message body ${timestamp}`;

    await page.goto("/newpost/test");

    // Fill in the form
    await page.fill("#postform-name", "Test User");
    await page.fill("#postform-email", "test@example.com");
    await page.fill("#postform-subject", testSubject);
    await page.fill("#postform-text", testBody);

    // Click "Save and preview" button
    await page.click('input[name="action-save"]');

    // Verify preview is shown - the page should show the message content
    await expect(page.locator("body")).toContainText(testBody);

    // Form should still be visible for editing
    await expect(page.locator("#postform")).toBeVisible();
  });

  test("spam detection triggers CAPTCHA challenge", async ({ page }) => {
    const timestamp = Date.now();
    // "spamtest" in subject triggers SimpleChecker's spam detection
    const testSubject = `spamtest ${timestamp}`;
    const testBody = `Testing CAPTCHA flow ${timestamp}`;

    await page.goto("/newpost/test");

    // Fill in the form with spam-triggering subject
    await page.fill("#postform-name", "Test User");
    await page.fill("#postform-email", "test@example.com");
    await page.fill("#postform-subject", testSubject);
    await page.fill("#postform-text", testBody);

    // Submit the form
    await page.click('input[name="action-send"]');

    // Should be challenged with CAPTCHA (dummy checkbox)
    // The page should show the CAPTCHA checkbox
    const captchaCheckbox = page.locator('input[name="dummy_captcha_checkbox"]');
    await expect(captchaCheckbox).toBeVisible();

    // Should show "I am not a robot" text
    await expect(page.locator("body")).toContainText("I am not a robot");

    // Form should still be visible with our data preserved
    await expect(page.locator("#postform")).toBeVisible();
    await expect(page.locator("#postform-subject")).toHaveValue(testSubject);
  });

  test("solving CAPTCHA allows post submission", async ({ page }) => {
    const timestamp = Date.now();
    // "spamtest" in subject triggers SimpleChecker's spam detection
    const testSubject = `spamtest solved ${timestamp}`;
    const testBody = `Testing CAPTCHA solution ${timestamp}`;

    await page.goto("/newpost/test");

    // Fill in the form with spam-triggering subject
    await page.fill("#postform-name", "Test User");
    await page.fill("#postform-email", "test@example.com");
    await page.fill("#postform-subject", testSubject);
    await page.fill("#postform-text", testBody);

    // Submit the form - should trigger CAPTCHA
    await page.click('input[name="action-send"]');

    // Wait for CAPTCHA checkbox to appear
    const captchaCheckbox = page.locator('input[name="dummy_captcha_checkbox"]');
    await expect(captchaCheckbox).toBeVisible();

    // Check the CAPTCHA checkbox
    await captchaCheckbox.check();

    // Submit again with CAPTCHA solved
    await page.click('input[name="action-send"]');

    // Should redirect to the posted thread
    await expect(page).toHaveURL(/\/(thread|post)\//);

    // Verify the post content is visible
    await expect(page.locator("body")).toContainText(testSubject);
    await expect(page.locator("body")).toContainText(testBody);
  });

  test("CAPTCHA-solved post appears in group listing", async ({ page }) => {
    const timestamp = Date.now();
    const testSubject = `spamtest listing ${timestamp}`;
    const testBody = `CAPTCHA listing test ${timestamp}`;

    await page.goto("/newpost/test");

    // Fill in and submit with spam-triggering subject
    await page.fill("#postform-name", "Test User");
    await page.fill("#postform-email", "test@example.com");
    await page.fill("#postform-subject", testSubject);
    await page.fill("#postform-text", testBody);
    await page.click('input[name="action-send"]');

    // Solve CAPTCHA
    const captchaCheckbox = page.locator('input[name="dummy_captcha_checkbox"]');
    await expect(captchaCheckbox).toBeVisible();
    await captchaCheckbox.check();
    await page.click('input[name="action-send"]');

    // Wait for posting to complete
    await expect(page).toHaveURL(/\/(thread|post)\//);

    // Navigate to group listing
    await page.goto("/group/test");

    // Verify the new thread appears in the listing
    await expect(page.locator("body")).toContainText(testSubject);
  });

  test("hard spam detection triggers CAPTCHA challenge", async ({ page }) => {
    const timestamp = Date.now();
    // "hardspamtest" in subject triggers certainlySpam (1.0) response
    const testSubject = `hardspamtest ${timestamp}`;
    const testBody = `Testing hard spam moderation flow ${timestamp}`;

    await page.goto("/newpost/test");

    // Fill in the form with hard spam-triggering subject
    await page.fill("#postform-name", "Test User");
    await page.fill("#postform-email", "test@example.com");
    await page.fill("#postform-subject", testSubject);
    await page.fill("#postform-text", testBody);

    // Submit the form
    await page.click('input[name="action-send"]');

    // Should be challenged with CAPTCHA (dummy checkbox)
    const captchaCheckbox = page.locator('input[name="dummy_captcha_checkbox"]');
    await expect(captchaCheckbox).toBeVisible();

    // Should show "I am not a robot" text
    await expect(page.locator("body")).toContainText("I am not a robot");
  });

  test("hard spam post is quarantined after solving CAPTCHA", async ({
    page,
  }) => {
    const timestamp = Date.now();
    // "hardspamtest" in subject triggers certainlySpam (1.0) response
    const testSubject = `hardspamtest moderated ${timestamp}`;
    const testBody = `Testing hard spam quarantine ${timestamp}`;

    await page.goto("/newpost/test");

    // Fill in the form with hard spam-triggering subject
    await page.fill("#postform-name", "Test User");
    await page.fill("#postform-email", "test@example.com");
    await page.fill("#postform-subject", testSubject);
    await page.fill("#postform-text", testBody);

    // Submit the form - should trigger CAPTCHA
    await page.click('input[name="action-send"]');

    // Wait for CAPTCHA checkbox to appear
    const captchaCheckbox = page.locator('input[name="dummy_captcha_checkbox"]');
    await expect(captchaCheckbox).toBeVisible();

    // Check the CAPTCHA checkbox
    await captchaCheckbox.check();

    // Submit again with CAPTCHA solved
    await page.click('input[name="action-send"]');

    // Should NOT redirect to thread - should show moderation message
    // The URL should stay on posting page (not redirect to thread)
    await expect(page).not.toHaveURL(/\/(thread|post)\//);

    // Should show moderation message
    await expect(page.locator("body")).toContainText(
      "approved by a moderator"
    );
  });

  test("quarantined post does not appear in group listing", async ({ page }) => {
    const timestamp = Date.now();
    const testSubject = `hardspamtest hidden ${timestamp}`;
    const testBody = `This post should be hidden ${timestamp}`;

    await page.goto("/newpost/test");

    // Fill in and submit with hard spam-triggering subject
    await page.fill("#postform-name", "Test User");
    await page.fill("#postform-email", "test@example.com");
    await page.fill("#postform-subject", testSubject);
    await page.fill("#postform-text", testBody);
    await page.click('input[name="action-send"]');

    // Solve CAPTCHA
    const captchaCheckbox = page.locator('input[name="dummy_captcha_checkbox"]');
    await expect(captchaCheckbox).toBeVisible();
    await captchaCheckbox.check();
    await page.click('input[name="action-send"]');

    // Should show moderation message
    await expect(page.locator("body")).toContainText(
      "approved by a moderator"
    );

    // Navigate to group listing
    await page.goto("/group/test");

    // Verify the quarantined thread does NOT appear in the listing
    await expect(page.locator("body")).not.toContainText(testSubject);
  });
});

test.describe("Registered User Experience", () => {
  test("registered user data persists after clearing cookies and signing back in", async ({
    page,
    context,
  }) => {
    const timestamp = Date.now();
    const testUsername = `testuser${timestamp}`;
    const testPassword = "testpass123";
    const testName = `Test User ${timestamp}`;
    const testEmail = `test${timestamp}@example.com`;
    const testSubject = `Registered User Test ${timestamp}`;
    const testBody = `Testing registered user persistence ${timestamp}`;

    // Step 1: Register a new user
    await page.goto("/registerform");
    await expect(page.locator("#registerform")).toBeVisible();

    await page.fill("#loginform-username", testUsername);
    await page.fill("#loginform-password", testPassword);
    await page.fill("#loginform-password2", testPassword);
    await page.click('input[type="submit"]');

    // Should be redirected after successful registration
    await expect(page).not.toHaveURL(/registerform/);

    // Step 2: Make a post (this saves name/email to user settings)
    await page.goto("/newpost/test");
    await expect(page.locator("#postform")).toBeVisible();

    await page.fill("#postform-name", testName);
    await page.fill("#postform-email", testEmail);
    await page.fill("#postform-subject", testSubject);
    await page.fill("#postform-text", testBody);
    await page.click('input[name="action-send"]');

    // Wait for posting to complete and verify post is displayed
    await expect(page).toHaveURL(/\/(thread|post)\//);
    await expect(page.locator("body")).toContainText(testSubject);
    await expect(page.locator("body")).toContainText(testBody);

    // Step 3: Clear cookies (simulating browser close/cookie expiration)
    await context.clearCookies();

    // Step 4: Sign back in
    await page.goto("/loginform");
    await expect(page.locator("#loginform")).toBeVisible();

    await page.fill("#loginform-username", testUsername);
    await page.fill("#loginform-password", testPassword);
    // Ensure "Remember me" is checked for persistent session
    await page.check("#loginform-remember");
    await page.click('input[type="submit"]');

    // Wait for navigation to complete (either redirect or error page)
    await page.waitForLoadState("networkidle");

    // Verify we're redirected (not on login page)
    await expect(page).not.toHaveURL(/\/login/);

    // Verify user is logged in by checking for logout link with username
    await expect(
      page.locator(`a:has-text("Log out ${testUsername}")`)
    ).toBeVisible();

    // Step 5a: Check that the post is marked as read
    await page.goto("/group/test");

    // Find the link to our test post - it should have the "forum-read" class
    const postLink = page.locator(`a:has-text("${testSubject}")`).first();
    await expect(postLink).toBeVisible();
    await expect(postLink).toHaveClass(/forum-read/);

    // Step 5b: Check that posting form has same user details pre-filled
    await page.goto("/newpost/test");
    await expect(page.locator("#postform")).toBeVisible();

    // Verify name and email are pre-filled with the same values
    await expect(page.locator("#postform-name")).toHaveValue(testName);
    await expect(page.locator("#postform-email")).toHaveValue(testEmail);
  });
});
