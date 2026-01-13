import { test, expect } from "@playwright/test";
import { execSync } from "child_process";
import path from "path";

const PROJECT_ROOT = path.resolve(__dirname, "..");
const DB_PATH = process.env.DFEED_DB || path.join(PROJECT_ROOT, "data/db/dfeed.s3db");

test("capture moderator journey view", { timeout: 30000 }, async ({ page, context, baseURL }) => {
  const timestamp = Date.now();
  const modUsername = `mod${timestamp}`;

  // Step 1: Register a moderator user first
  await page.goto("/registerform");
  await page.fill("#loginform-username", modUsername);
  await page.fill("#loginform-password", "testpass123");
  await page.fill("#loginform-password2", "testpass123");
  await page.click('input[type="submit"]');
  await page.waitForURL("**/");

  console.log(`Registered moderator user: ${modUsername}`);

  // Step 2: Update user to full moderator level (100) via SQL
  // Level 90 = canApproveDrafts, Level 100 = canModerate (can access /moderate/ page)
  const sqlCmd = `UPDATE Users SET Level=100 WHERE Username='${modUsername}';`;
  console.log(`Running SQL: ${sqlCmd}`);
  execSync(`sqlite3 "${DB_PATH}" "${sqlCmd}"`);
  console.log("User promoted to moderator");

  // Step 3: Create a moderated draft as anonymous user
  // Clear cookies to act as new anonymous user
  await context.clearCookies();

  await page.goto("/newpost/test");
  await expect(page.locator("#postform")).toBeVisible();

  // Fill form with hardspamtest (triggers CAPTCHA AND moderation)
  await page.fill("#postform-name", "Test User");
  await page.fill("#postform-email", "test@example.com");
  await page.fill("#postform-subject", `hardspamtest ${timestamp}`);
  await page.fill("#postform-text", "Testing CAPTCHA question logging and moderation journey");

  // Submit to trigger CAPTCHA
  await page.click('input[name="action-send"]');

  // Wait for CAPTCHA
  const captchaCheckbox = page.locator('input[name="dummy_captcha_checkbox"]');
  await expect(captchaCheckbox).toBeVisible();

  // Capture the draft ID (did) from the hidden form field before solving CAPTCHA
  const draftId = await page.locator('input[name="did"]').inputValue();
  console.log(`Draft ID (did): ${draftId}`);

  // Screenshot 1: CAPTCHA challenge
  await page.screenshot({ path: path.join(__dirname, "screenshot-captcha-1-challenge.png"), fullPage: true });

  // Solve CAPTCHA
  await captchaCheckbox.check();
  await page.click('input[name="action-send"]');

  // Wait for moderation notice
  await expect(page.locator("body")).toContainText("approved by a moderator", { timeout: 10000 });

  // Screenshot 2: Moderation notice
  await page.screenshot({ path: path.join(__dirname, "screenshot-captcha-2-moderation-notice.png"), fullPage: true });

  // Step 4: Log in as moderator
  await page.goto("/loginform");
  await page.fill("#loginform-username", modUsername);
  await page.fill("#loginform-password", "testpass123");
  await page.click('input[type="submit"]');
  await page.waitForURL("**/");

  // Step 5: Navigate to the moderation approval page and approve the post
  if (draftId) {
    await page.goto(`/approve-moderated-draft/${draftId}`);
    await page.waitForTimeout(500);

    // Screenshot 3: Approval confirmation page
    await page.screenshot({ path: path.join(__dirname, "screenshot-captcha-3-approval-page.png"), fullPage: true });

    // Click Approve button
    await page.click('input[name="approve"]');
    await page.waitForTimeout(1000);

    // Screenshot 4: Post approved confirmation
    await page.screenshot({ path: path.join(__dirname, "screenshot-captcha-4-post-approved.png"), fullPage: true });

    // Extract the posting link to get the message ID
    const viewLink = await page.locator('a:has-text("View posting")').getAttribute('href');
    console.log(`View posting link: ${viewLink}`);

    if (viewLink) {
      // Get the post ID from /posting/<postID>
      const postIdMatch = viewLink.match(/posting\/([a-z]+)/);
      if (postIdMatch) {
        const postId = postIdMatch[1];
        // The message ID format is <postID@localhost>
        const encodedMessageId = encodeURIComponent(`${postId}@localhost`);

        // Navigate to the moderation page to see the journey view
        await page.goto(`/moderate/${encodedMessageId}`);
        await page.waitForTimeout(500);

        // Screenshot 5: User Journey view with CAPTCHA question/answer
        await page.screenshot({ path: path.join(__dirname, "screenshot-captcha-5-journey-view.png"), fullPage: true });
        console.log("Captured user journey view with CAPTCHA question/answer");
      }
    }
  }
});
