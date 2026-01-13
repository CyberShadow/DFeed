import { test, expect } from "@playwright/test";
import { execSync } from "child_process";
import path from "path";

const PROJECT_ROOT = path.resolve(__dirname, "..");
const DB_PATH = process.env.DFEED_DB || path.join(PROJECT_ROOT, "data/db/dfeed.s3db");

test.describe("Deleted Post Moderation", () => {
  test("shows user journey and deletion record for deleted post", async ({ page, context }) => {
    const timestamp = Date.now();
    const modUsername = `mod${timestamp}`;
    const testSubject = `Delete Test ${timestamp}`;
    const testBody = `This post will be deleted ${timestamp}`;

    // Step 1: Register a moderator user
    await page.goto("/registerform");
    await page.fill("#loginform-username", modUsername);
    await page.fill("#loginform-password", "testpass123");
    await page.fill("#loginform-password2", "testpass123");
    await page.click('input[type="submit"]');
    await page.waitForURL("**/");

    // Promote user to moderator level (100)
    const sqlCmd = `UPDATE Users SET Level=100 WHERE Username='${modUsername}';`;
    execSync(`sqlite3 "${DB_PATH}" "${sqlCmd}"`);

    // Step 2: Create a post that triggers CAPTCHA (so we have journey data)
    await context.clearCookies();

    await page.goto("/newpost/test");
    await expect(page.locator("#postform")).toBeVisible();

    // Use "spamtest" to trigger CAPTCHA but NOT hard moderation
    await page.fill("#postform-name", "Test User");
    await page.fill("#postform-email", "test@example.com");
    await page.fill("#postform-subject", `spamtest ${testSubject}`);
    await page.fill("#postform-text", testBody);

    // Submit to trigger CAPTCHA
    await page.click('input[name="action-send"]');

    // Wait for CAPTCHA and solve it
    const captchaCheckbox = page.locator('input[name="dummy_captcha_checkbox"]');
    await expect(captchaCheckbox).toBeVisible();
    await captchaCheckbox.check();
    await page.click('input[name="action-send"]');

    // Wait for redirect to the posted thread
    await expect(page).toHaveURL(/\/(thread|post)\//, { timeout: 10000 });

    // Extract the post ID from the URL
    const url = page.url();
    const postIdMatch = url.match(/\/(thread|post)\/([a-z]+)/);
    expect(postIdMatch).toBeTruthy();
    const postId = postIdMatch![2];
    const encodedMessageId = encodeURIComponent(`${postId}@localhost`);

    // Step 3: Log in as moderator
    await page.goto("/loginform");
    await page.fill("#loginform-username", modUsername);
    await page.fill("#loginform-password", "testpass123");
    await page.click('input[type="submit"]');
    await page.waitForURL("**/");

    // Step 4: Go to moderation page and delete the post
    await page.goto(`/moderate/${encodedMessageId}`);

    // Verify the post content is shown (before deletion)
    await expect(page.locator("#deleteform-message")).toBeVisible();
    await expect(page.locator("#deleteform-message")).toContainText(testBody);

    // Verify user journey is shown before deletion
    const journeyBeforeDeletion = page.locator(".journey-timeline");
    await expect(journeyBeforeDeletion).toBeVisible();

    // Delete the post (only local copy, don't ban)
    await page.check("#deleteform-delete");
    await page.fill('input[name="reason"]', "test deletion");
    await page.click('input[type="submit"]');

    // Verify deletion confirmation
    await expect(page.locator("body")).toContainText("Post deleted");

    // Step 5: Visit the moderation page again for the now-deleted post
    await page.goto(`/moderate/${encodedMessageId}`);

    // Verify "not in database" notice is shown
    await expect(page.locator(".forum-notice")).toContainText("not in the database");

    // Verify User Journey section still exists (from PostProcess logs)
    const journeySection = page.locator(".journey-timeline");
    await expect(journeySection).toBeVisible();

    // Verify CAPTCHA events are still visible in journey
    const captchaQuestion = journeySection.locator(".journey-event", {
      has: page.locator(".journey-message", { hasText: "CAPTCHA question" })
    });
    await expect(captchaQuestion.first()).toBeVisible();

    // Verify Deletion Record section is shown
    await expect(page.locator("body")).toContainText("Deletion Record");

    // Verify deletion metadata
    await expect(page.locator("body")).toContainText("Deleted by:");
    await expect(page.locator("body")).toContainText(modUsername);
    await expect(page.locator("body")).toContainText("Reason:");
    await expect(page.locator("body")).toContainText("test deletion");

    // Verify original message content is preserved
    await expect(page.locator("#deleteform-message")).toBeVisible();
    await expect(page.locator("#deleteform-message")).toContainText(testBody);
  });

  test("shows appropriate message for non-existent post with no logs", async ({ page, context }) => {
    const timestamp = Date.now();
    const modUsername = `mod${timestamp}`;

    // Register and promote to moderator
    await page.goto("/registerform");
    await page.fill("#loginform-username", modUsername);
    await page.fill("#loginform-password", "testpass123");
    await page.fill("#loginform-password2", "testpass123");
    await page.click('input[type="submit"]');
    await page.waitForURL("**/");

    const sqlCmd = `UPDATE Users SET Level=100 WHERE Username='${modUsername}';`;
    execSync(`sqlite3 "${DB_PATH}" "${sqlCmd}"`);

    // Log in as moderator
    await page.goto("/loginform");
    await page.fill("#loginform-username", modUsername);
    await page.fill("#loginform-password", "testpass123");
    await page.click('input[type="submit"]');
    await page.waitForURL("**/");

    // Visit moderation page for a non-existent message ID
    const fakeMessageId = encodeURIComponent(`nonexistent${timestamp}@localhost`);
    await page.goto(`/moderate/${fakeMessageId}`);

    // Should show "not in database" notice
    await expect(page.locator(".forum-notice")).toContainText("not in the database");

    // Should NOT show journey timeline (no logs exist)
    await expect(page.locator(".journey-timeline")).not.toBeVisible();

    // Should NOT show deletion record (never existed)
    await expect(page.locator("body")).not.toContainText("Deletion Record");
  });
});
