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
});
