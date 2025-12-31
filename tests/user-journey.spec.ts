import { test, expect } from "@playwright/test";
import { execSync } from "child_process";
import path from "path";

const PROJECT_ROOT = path.resolve(__dirname, "..");
const DB_PATH = process.env.DFEED_DB || path.join(PROJECT_ROOT, "data/db/dfeed.s3db");

test.describe("User Journey", () => {
  test("shows CAPTCHA question and answer on approval and moderation pages", async ({ page, context }) => {
    const timestamp = Date.now();
    const modUsername = `mod${timestamp}`;

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

    // Step 2: Create a moderated post as anonymous user
    await context.clearCookies();

    await page.goto("/newpost/test");
    await expect(page.locator("#postform")).toBeVisible();

    // Fill form with hardspamtest (triggers CAPTCHA AND moderation)
    await page.fill("#postform-name", "Test User");
    await page.fill("#postform-email", "test@example.com");
    await page.fill("#postform-subject", `hardspamtest ${timestamp}`);
    await page.fill("#postform-text", "Testing CAPTCHA question and answer in user journey");

    // Submit to trigger CAPTCHA
    await page.click('input[name="action-send"]');

    // Wait for CAPTCHA and solve it
    const captchaCheckbox = page.locator('input[name="dummy_captcha_checkbox"]');
    await expect(captchaCheckbox).toBeVisible();

    // Capture the draft ID before solving CAPTCHA
    const draftId = await page.locator('input[name="did"]').inputValue();
    expect(draftId).toBeTruthy();

    // Solve CAPTCHA and submit
    await captchaCheckbox.check();
    await page.click('input[name="action-send"]');

    // Wait for moderation notice
    await expect(page.locator("body")).toContainText("approved by a moderator", { timeout: 10000 });

    // Step 3: Log in as moderator
    await page.goto("/loginform");
    await page.fill("#loginform-username", modUsername);
    await page.fill("#loginform-password", "testpass123");
    await page.click('input[type="submit"]');
    await page.waitForURL("**/");

    // Step 4: Check the approval page has User Journey with CAPTCHA info
    await page.goto(`/approve-moderated-draft/${draftId}`);

    // Verify User Journey section exists
    const journeySection = page.locator(".journey-timeline");
    await expect(journeySection).toBeVisible();

    // Verify CAPTCHA question is shown (use .journey-message for more specific matching)
    const captchaQuestion = journeySection.locator(".journey-event", { has: page.locator(".journey-message", { hasText: "CAPTCHA question" }) });
    await expect(captchaQuestion.first()).toBeVisible();
    await expect(captchaQuestion.first()).toContainText("Dummy CAPTCHA");

    // Verify CAPTCHA answer is shown
    const captchaAnswer = journeySection.locator(".journey-event", { has: page.locator(".journey-message", { hasText: "CAPTCHA answer" }) });
    await expect(captchaAnswer.first()).toBeVisible();
    await expect(captchaAnswer.first()).toContainText("checked", { ignoreCase: true });

    // Step 5: Approve the post
    await page.click('input[name="approve"]');
    await expect(page.locator("body")).toContainText("Post approved");

    // Get the posting link to find the message ID
    const viewLink = await page.locator('a:has-text("View posting")').getAttribute('href');
    expect(viewLink).toBeTruthy();

    const postIdMatch = viewLink!.match(/posting\/([a-z]+)/);
    expect(postIdMatch).toBeTruthy();

    const postId = postIdMatch![1];
    const encodedMessageId = encodeURIComponent(`${postId}@localhost`);

    // Step 6: Check the moderation page for the live post also has User Journey with CAPTCHA info
    await page.goto(`/moderate/${encodedMessageId}`);

    // Verify User Journey section exists
    const moderationJourney = page.locator(".journey-timeline");
    await expect(moderationJourney).toBeVisible();

    // Verify CAPTCHA question is shown (use .journey-message for more specific matching)
    const modCaptchaQuestion = moderationJourney.locator(".journey-event", { has: page.locator(".journey-message", { hasText: "CAPTCHA question" }) });
    await expect(modCaptchaQuestion.first()).toBeVisible();
    await expect(modCaptchaQuestion.first()).toContainText("Dummy CAPTCHA");

    // Verify CAPTCHA answer is shown
    const modCaptchaAnswer = moderationJourney.locator(".journey-event", { has: page.locator(".journey-message", { hasText: "CAPTCHA answer" }) });
    await expect(modCaptchaAnswer.first()).toBeVisible();
    await expect(modCaptchaAnswer.first()).toContainText("checked", { ignoreCase: true });
  });
});
