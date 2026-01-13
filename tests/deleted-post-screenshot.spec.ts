import { test, expect } from "@playwright/test";
import { execSync } from "child_process";
import path from "path";

const PROJECT_ROOT = path.resolve(__dirname, "..");
const DB_PATH = process.env.DFEED_DB || path.join(PROJECT_ROOT, "data/db/dfeed.s3db");

test("capture deleted post moderation view", { timeout: 60000 }, async ({ page, context }) => {
  const timestamp = Date.now();
  const modUsername = `mod${timestamp}`;

  // Step 1: Register a moderator user
  await page.goto("/registerform");
  await page.fill("#loginform-username", modUsername);
  await page.fill("#loginform-password", "testpass123");
  await page.fill("#loginform-password2", "testpass123");
  await page.click('input[type="submit"]');
  await page.waitForURL("**/");

  console.log(`Registered moderator user: ${modUsername}`);

  // Promote to moderator level
  const sqlCmd = `UPDATE Users SET Level=100 WHERE Username='${modUsername}';`;
  execSync(`sqlite3 "${DB_PATH}" "${sqlCmd}"`);
  console.log("User promoted to moderator");

  // Step 2: Create a post as anonymous user (with CAPTCHA to generate journey logs)
  await context.clearCookies();

  await page.goto("/newpost/test");
  await expect(page.locator("#postform")).toBeVisible();

  // Use "spamtest" to trigger CAPTCHA but NOT hard moderation (so post goes through)
  await page.fill("#postform-name", "Test Spammer");
  await page.fill("#postform-email", "spammer@example.com");
  await page.fill("#postform-subject", `spamtest Delete Demo ${timestamp}`);
  await page.fill("#postform-text", "This post will be deleted to demonstrate the deleted post moderation view.\n\nIt shows the user journey and deletion record even after the post is removed from the database.");

  // Submit to trigger CAPTCHA
  await page.click('input[name="action-send"]');

  // Solve CAPTCHA
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
  console.log(`Created post with ID: ${postId}`);

  // Step 3: Log in as moderator
  await page.goto("/loginform");
  await page.fill("#loginform-username", modUsername);
  await page.fill("#loginform-password", "testpass123");
  await page.click('input[type="submit"]');
  await page.waitForURL("**/");

  // Step 4: Go to moderation page and take screenshot before deletion
  await page.goto(`/moderate/${encodedMessageId}`);
  await page.waitForTimeout(500);

  // Screenshot 1: Moderation page before deletion
  await page.screenshot({
    path: path.join(__dirname, "screenshot-deleted-1-before.png"),
    fullPage: true
  });
  console.log("Screenshot 1: Moderation page before deletion");

  // Step 5: Delete the post
  await page.check("#deleteform-delete");
  await page.fill('input[name="reason"]', "spam demo");
  await page.click('input[type="submit"]');

  // Wait for deletion confirmation
  await expect(page.locator("body")).toContainText("Post deleted");
  await page.waitForTimeout(500);

  // Screenshot 2: Deletion confirmation
  await page.screenshot({
    path: path.join(__dirname, "screenshot-deleted-2-confirmation.png"),
    fullPage: true
  });
  console.log("Screenshot 2: Deletion confirmation");

  // Step 6: Visit the moderation page again for the deleted post
  await page.goto(`/moderate/${encodedMessageId}`);
  await page.waitForTimeout(500);

  // Screenshot 3: Deleted post moderation view with journey and deletion record
  await page.screenshot({
    path: path.join(__dirname, "screenshot-deleted-3-after.png"),
    fullPage: true
  });
  console.log("Screenshot 3: Deleted post moderation view");

  // Verify the key elements are present
  await expect(page.locator(".forum-notice")).toContainText("not in the database");
  await expect(page.locator(".journey-timeline")).toBeVisible();
  await expect(page.locator("body")).toContainText("Deletion Record");
  await expect(page.locator("body")).toContainText(`Deleted by:`);
  await expect(page.locator("body")).toContainText(modUsername);
});
