/*  Copyright (C) 2020  Vladimir Panteleev <vladimir@thecybershadow.net>
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Affero General Public License as
 *  published by the Free Software Foundation, either version 3 of the
 *  License, or (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

module dfeed.loc.turkish;

enum languageName = "Türkçe";
enum languageCode = "tr";
enum digitGroupingSeparator = '.';

string translate(string s)
{
	switch (s)
	{
		case `Please enter a name`:
			return `Lütfen bir isim giriniz`;
		case `Please enter an email address`:
			return `Lütfen bir e-posta adresi giriniz`;
		case `Please enter a message subject`:
			return `Lütfen bir mesaj konusu giriniz`;
		case `Please enter a message`:
			return `Lütfen bir mesaj giriniz`;
		case `CAPTCHA error:`:
			return `CAPTCHA hatası:`;
		case `You can't post to this group.`:
			return `Bu gruba mesaj gönderemezsiniz.`;
		case `NNTP connection error:`:
			return `NNTP bağlantı hatası:`;
		case `NNTP error:`:
			return `NNTP hatası:`;
		case `Posting is disabled`:
			return `Gönderim hizmet dışı`;
		case `SMTP error:`:
			return `SMTP hatası:`;
		case `Post not found`:
			return `Gönderi bulunamadı`;
		case `Invalid attachment`:
			return `Geçersiz ek`;
		case `Guest`:
			return `Misafir`;
		case `Welcome back,`:
			return `Tekrar hoşgeldiniz,`;
		case `Welcome,`:
			return `Hoşgeldiniz,`;
		case `You have %d %s to %syour posts%s.`:
			return `%3$sGönderilerinize%4$s %1$d %2$s var.`;
		case `No new %sreplies%s to %syour posts%s.`:
			return `%3$sGönderilerinize%4$s yeni %1$syanıt yok%2$s.`;
		case `You have %d %s matching your %s%s subscription%s (%s).`:
			return `%3$s%4$s aboneliğinizle%5$s eşleşen %1$d %2$s var (%6$s).`;
		case `No new posts matching your %s%s%s.`:
			return `%s%s%s ile eşleşen yeni gönderi yok.`;
		case `If you %screate an account%s, you can track replies to %syour posts%s.`:
			return `%sHesap açtığınızda%s %sgönderilerinize%s gelen yanıtları izleyebilirsiniz.`;
		case `You can read and post on this forum without %screating an account%s, but creating an account offers %sa few benefits%s.`:
			return `Bu forumu hesap açmadan da kullanabilirsiniz. Ancak, %shesap açmanın%s bazı %syararları vardır%s.`;
		case `%d %s %-(%s and %)`:
			return `%d %s %-(%s ve %) oluşturdu.`;
		case `No new forum activity`:
			return `Yeni forum etkinliği yok`;
		case `since your last visit (%s).`:
			return `(son ziyaretinizden beri (%s)).`;
		case `in the last 24 hours.`:
			return `(son 24 saat içinde).`;
		case `There are %s %s, %s %s, and %s %s on this forum.`:
			return `Bu forumda %s %s, %s %s ve %s %s var.`;
		case `You have read a total of %s %s during your %s.`:
			return `%3$s sırasında toplam %1$s %2$s okudunuz.`;
		case `Random tip:`:
			return `Bilgi:`;
		case `This forum has several different <a href="/help#view-modes">view modes</a>. Try them to find one you like best. You can change the view mode in the <a href="/settings">settings</a>.`:
			return `Bu forumun birkaç farklı <a href="/help#view-modes">görünümü</a> bulunuyor. Kullanışlı bulduğunuz birini seçin. Görünüm seçeneğini <a href="/settings">ayarlardan</a> değiştirebilirsiniz.`;
		case `This forum supports <a href="/help#keynav">keyboard shortcuts</a>. Press <kbd>?</kbd> to view them.`:
			return `Bu forum <a href="/help#keynav">klavye kısayolları</a> kullanır. Görüntülemek için <kbd>?</kbd> tuşuna basın.`;
		case `You can focus a message with <kbd>j</kbd>/<kbd>k</kbd> and press <kbd>u</kbd> to mark it as unread, to remind you to read it later.`:
			return `Bir mesajı <kbd>j</kbd> ve <kbd>k</kbd> tuşları ile seçebilir ve <kbd>u</kbd> tuşu ile okunmadı olarak işaretleyebilirsiniz.`;
		case `The <a href="/help#avatars">avatars on this forum</a> are provided by Gravatar, which allows associating a global avatar with an email address.`:
			return `<a href="/help#avatars">Bu forumdaki avatarlar</a>, global bir avatarın bir e-posta adresiyle ilişkilendirilmesini sağlayan Gravatar tarafından sağlanmaktadır.`;
		case `This forum remembers your read post history on a per-post basis. If you are logged in, the post history is saved on the server, and in a compressed cookie otherwise.`:
			return `Bu forum, okumuş olduğunuz gönderileri hatırlar. Bu bilgi, giriş yapmışsanız sunucuda, aksi takdirde sıkıştırılmış bir çerez olarak tarayıcınızda saklanır.`;
		case `Much of this forum's content is also available via classic mailing lists or NNTP - see the "Also via" column on the forum index.`:
			return `Bu forumun içeriğinin çoğuna e-posta listeleri veya NNTP aracılığıyla da erişilebilir - forum dizinindeki "Ayrıca" sütununa bakınız.`;
		case `If you create a Gravatar profile with the email address you post with, it will be accessible when clicking your avatar.`:
			return `Gönderdiğiniz e-posta adresiyle bir Gravatar profili oluşturursanız, avatarınıza tıkladığınızda erişilebilir olacaktır.`;
		case `To subscribe to a thread, click the "Subscribe" link on that thread's first post. You need to be logged in to create subscriptions.`:
			return `Bir konuya abone olmak için o konunun ilk gönderisindeki "Abone ol" bağlantısını tıklayın. Abonelik oluşturmak için giriş yapmış olmalısınız.`;
		case `To search the forum, use the search widget at the top, or you can visit <a href="/search">the search page</a> directly.`:
			return `Forumda arama yapmak için üstteki arama olanağını kullabilirsiniz veya doğrudan <a href="/search">arama sayfasına</a> gidebilirsiniz.`;
		case `This forum is open-source! Read or fork the code <a href="https://github.com/CyberShadow/DFeed">on GitHub</a>.`:
			return `Bu forum açık kaynaklıdır! Kaynak kodunu <a href="https://github.com/CyberShadow/DFeed">GitHub'da</a> okuyun veya çatallayın.`;
		case `If you encounter a bug or need a missing feature, you can <a href="https://github.com/CyberShadow/DFeed/issues">create an issue on GitHub</a>.`:
			return `Farkettiğiniz hataları ve eksik özellikleri <a href="https://github.com/CyberShadow/DFeed/issues">GitHub'da bildirebilirsiniz</a>.`;
		case `Group`:
			return `Grup`;
		case `Last Post`:
			return `Son Gönderi`;
		case `Threads`:
			return `Konu`;
		case `Posts`:
			return `Gönderi`;
		case `Also via`:
			return `Ayrıca`;
		case `Create thread`:
			return `Yeni konu aç`;
		case `Invalid page`:
			return `Geçersiz sayfa`;
		case `by`:
			return ``;
		case `Thread / Thread Starter`:
			return `Konu / Konuyu Başlatan`;
		case `Replies`:
			return `Yanıt`;
		case `Loading...`:
			return `Yükleniyor...`;
		case `Sorry, this view requires JavaScript.`:
			return `Üzgünüz, bu görünüm JavaScript gerektirmektedir.`;
		case `Unknown group:`:
			return `Bilinmeyen grup:`;
		case `Can't find thread's page`:
			return `Konu sayfası bulunamadı`;
		case `Can't find post's page`:
			return `Gönderi sayfası bulunamadı`;
		case `The specified resource cannot be found on this server.`:
			return `Belirtilen kaynak bu sunucuda bulunamıyor.`;
		case `XSRF secret verification failed. Are your cookies enabled?`:
			return `XSRF gizli doğrulaması başarısız oldu. Çerezleriniz etkin mi?`;
		case `No action specified`:
			return `Eylem belirtilmedi`;
		case `Subscription undeleted.`:
			return `Aboneliğin silinmesi geri alındı.`;
		case `Subscription saved.`:
			return `Abonelik kaydedildi.`;
		case `Subscription created.`:
			return `Abonelik oluşturuldu.`;
		case `This subscription doesn't exist.`:
			return `Bu abonelik mevcut değil.`;
		case `Subscription deleted.`:
			return `Abonelik silindi.`;
		case `Unknown action:`:
			return `Bilinmeyen eylem:`;
		case `Settings`:
			return `Ayarlar`;
		case `User Interface`:
			return `Kullanıcı arayüzü`;
		case `Language:`:
			return `Dil:`;
		case `View mode:`:
			return `Görünüm:`;
		case `Enable keyboard shortcuts`:
			return `Klavye kısayollarını etkinleştir`;
		case `Automatically open messages after selecting them.`:
			return `Seçilen mesaj otomatik olarak açılır.`;
		case `Applicable to threaded, horizontal-split and vertical-split view modes.`:
			return `Gönderi listesi, yatay bölünmüş ve dikey bölünmüş görünümlere uygulanabilir.`;
		case `Focus follows message`:
			return `Mesaj otomatik açılsın`;
		case `Save`:
			return `Kaydet`;
		case `Cancel`:
			return `İptal et`;
		case `Subscriptions`:
			return `Konu abonelikleri`;
		case `Subscription`:
			return `Seçim`;
		case `Actions`:
			return `Eylemler`;
		case `View posts`:
			return `Gönderileri göster`;
		case `Get ATOM feed`:
			return `ATOM beslemesini indir`;
		case `Edit`:
			return `Düzenle`;
		case `Delete`:
			return `Sil`;
		case `You have no subscriptions.`:
			return `Aboneliğiniz yok.`;
		case `Create new content alert subscription`:
			return `Konu aboneliği oluştur`;
		case `Please %slog in%s to manage your subscriptions and account settings.`:
			return `Aboneliklerinizi ve hesap ayarlarınızı yönetebilmek için lütfen %sgiriş yapınız%s.`;
		case `Account settings`:
			return `Hesap ayarları`;
		case `Change the password used to log in to this account.`:
			return `Bu hesabın şifresini değiştir.`;
		case `Change password`:
			return `Şifre değiştir`;
		case `Download a file containing all data tied to this account.`:
			return `Bu hesaba bağlı tüm verileri içeren bir dosya indir.`;
		case `Export data`:
			return `Verileri dışa aktar`;
		case `Permanently delete this account.`:
			return `Bu hesabı kalıcı olarak sil.`;
		case `Delete account`:
			return `Hesabı sil`;
		case `Edit subscription`:
			return `Aboneliği düzenle`;
		case `Condition`:
			return `Seçim`;
		case `This action is only meaningful for logged-in users.`:
			return `Bu işlem yalnızca giriş yapmış kullanıcılar için anlamlıdır.`;
		case `Here you can change the password used to log in to this %s account.`:
			return `Burada, bu %s hesabının şifresini değiştirebilirsiniz.`;
		case `Please pick your new password carefully, as there are no password recovery options.`:
			return `Şifre kurtarma seçeneği olmadığından, lütfen yeni şifrenizi dikkatlice seçin.`;
		case `Current password:`:
			return `Mevcut şifre:`;
		case `New password:`:
			return `Yeni şifre:`;
		case `New password (confirm):`:
			return `Yeni şifre (onaylayın):`;
		case `XSRF secret verification failed`:
			return `XSRF gizli doğrulaması başarısız oldu`;
		case `The current password you entered is incorrect`:
			return `Girdiğiniz mevcut şifre yanlış`;
		case `New passwords do not match`:
			return `Yeni şifreler uyuşmuyor`;
		case `Password successfully changed.`:
			return `Şifre başarıyla değiştirildi.`;
		case `Export account data`:
			return `Hesap verilerini dışa aktar`;
		case `Here you can export the information regarding your account from the %s database.`:
			return `Burada hesabınızla ilgili bilgileri %s veritabanından dışa aktarabilirsiniz.`;
		case `Export`:
			return `Dışa aktar`;
		case `Here you can permanently delete your %s account and associated data from the database.`:
			return `Burada %s hesabınızı ve ilişkili verileri veritabanından kalıcı olarak silebilirsiniz.`;
		case `After deletion, the account username will become available for registration again.`:
			return `Silme işleminden sonra, hesap kullanıcı adı tekrar kayıt için uygun hale gelecektir.`;
		case `To confirm deletion, please enter your account username and password.`:
			return `Silme işlemini onaylamak için lütfen hesap kullanıcı adınızı ve şifrenizi giriniz.`;
		case `Account username:`:
			return `Hesap kullanıcı adı:`;
		case `Account password:`:
			return `Hesap şifresi:`;
		case `Delete this account`:
			return `Bu hesabı sil`;
		case `The username you entered does not match the current logged-in account`:
			return `Girdiğiniz kullanıcı adı, mevcut oturum açmış hesapla eşleşmiyor`;
		case `The password you entered is incorrect`:
			return `Girdiğiniz şifre yanlış`;
		case `Account successfully deleted!`:
			return `Hesap başarıyla silindi!`;
		case `Latest threads on %s`:
			return `%s üzerindeki son konular`;
		case `Latest posts on %s`:
			return `%s üzerindeki son gönderiler`;
		case `Latest threads`:
			return `Son konular`;
		case `Latest posts`:
			return `Son gönderiler`;
		case `%s subscription (%s)`:
			return `%s aboneliği (%s)`;
		case `No such subscription`:
			return `Böyle bir abonelik yok`;
		case `Not logged in`:
			return `Giriş yapmadınız`;
		case `No such user subscription`:
			return `Böyle bir kullanıcı aboneliği yok`;
		case `reply`:
			return `yanıt`;
		case `Replies to your posts`:
			return `Gönderilerinize verilen yanıtlar`;
		case `%s replied to your post in the thread "%s"`:
			return `%s, "%s" konusundaki gönderinize yanıt verdi`;
		case `%s has just replied to your %s post in the thread titled "%s" in the %s group of %s.`:
			return `%1$s, %5$s sunucusunun %4$s grubundaki "%3$s" başlıklı konusundaki %2$s gönderinize az önce yanıt verdi.`;
		case `When someone replies to your posts:`:
			return `Birisi gönderilerinize yanıt verdiğinde:`;
		case `thread`:
			return `konu`;
		case `Replies to the thread`:
			return `Konusu:`;
		case `%s replied to the thread "%s"`:
			return `%s, "%s" konusuna yanıt verdi`;
		case `%s has just replied to a thread you have subscribed to titled "%s" in the %s group of %s.`:
			return `%1$s, %4$s sunucusunun %3$s grubundaki abone olduğunuz "%2$s" başlıklı konuya yanıt verdi.`;
		case `When someone posts a reply to the thread`:
			return `Birisi şu konuya yanıt gönderdiğinde:`;
		case `No such post`:
			return `Böyle bir gönderi yok`;
		case `content`:
			return `içerik`;
		case `New threads`:
			return `Yeni konu veya gönderi;`;
		case `New posts`:
			return `Yeni gönderi;`;
		case `in`:
			return `grup(lar):`;
		case `and`:
			return `ve`;
		case `more`:
			return `tane daha`;
		case `from`:
			return `göndereni:`;
		case `from email`:
			return `e-postası:`;
		case `titled`:
			return `konusu:`;
		case `containing`:
			return `içeriği:`;
		case `%s %s the thread "%s" in %s`:
			return `%1$s, %4$s grubunun "%3$s" konusunu %2$s`;
		case `replied to`:
			return `yanıtladı`;
		case `created`:
			return `oluşturdu`;
		case `%s matching %s`:
			return `%s ile eşleşen %s`;
		case "%s has just %s a thread titled \"%s\" in the %s group of %s.\n\n%s matches a content alert subscription you have created (%s).":
			return "%1$s, %5$s sunucusunun %4$s grubundaki \"%3$s\" başlıklı konuyu %2$s.\n\n%6$s, oluşturduğunuz bir konu aboneliğiyle eşleşiyor (%7$s).";
		case `This post`:
			return `Bu gönderi`;
		case `This thread`:
			return `Bu konu`;
		case `When someone`:
			return `Birisi`;
		case `posts or replies to a thread`:
			return `yeni konu açarsa veya yanıtlarsa`;
		case `posts a new thread`:
			return `yeni konu açarsa`;
		case `only in the groups:`:
			return `grup şunlardan birisiyse:<br>(birden fazla seçmek için Ctrl-tık):`;
		case `and when the`:
			return `ve eğer`;
		case `contains the string`:
			return `şu dizgiyi içerirse:`;
		case `matches the regular expression`:
			return `şu düzenli ifadeyle (regex) eşleşirse:`;
		case `case sensitive`:
			return `küçük/büyük harfe duyarlı`;
		case `author name`:
			return `yazar adı`;
		case `author email`:
			return `yazar e-postası`;
		case `subject`:
			return `konu başlığı`;
		case `message`:
			return `ileti`;
		case `No %s search term specified`:
			return `%s arama terimi belirtilmedi`;
		case "Invalid %s regex `%s`: %s":
			return "Geçersiz %s düzenli ifadesi `%s`: %s";
		case `No groups selected`:
			return `Grup seçilmedi`;
		case `Unknown subscription trigger type:`:
			return `Bilinmeyen abonelik tetikleyici türü:`;
		case `Send a private message to`:
			return `Şu kişiye özel mesaj gönder:`;
		case `on the`:
			return `üzerinde`;
		case `IRC network`:
			return `IRC ağı`;
		case `No nickname indicated`:
			return `Takma ad belirtilmedi`;
		case `Invalid character in nickname.`:
			return `Takma adda geçersiz karakter.`;
		case `Send an email to`:
			return `Şu adrese e-posta gönder:`;
		case `Error:`:
			return `Hata:`;
		case `Howdy %1$s,`:
			return `Merhaba %1$s,`;
		case `This %3$s is located at:`:
			return `Bu %3$:`;
		case `Here is the message that has just been posted:`:
			return `Yeni gönderi:`;
		case `To reply to this message, please visit this page:`:
			return `Bu gönderiyi yanıtlamak için lütfen şu sayfayı ziyaret edin:`;
		case `There may also be other messages matching your subscription, but you will not receive any more notifications for this subscription until you've read all messages matching this subscription:`:
			return `Aboneliğinizle eşleşen başka mesajlar da olabilir, ancak bu abonelikle eşleşen tüm mesajları okuyana kadar bu abonelik için başka bildirim almayacaksınız:`;
		case `All the best,`:
			return `Herşey gönlünüzce olsun,`;
		case `Unsubscription information:`:
			return `Abonelik iptali bilgileri:`;
		case `To stop receiving emails for this subscription, please visit this page:`:
			return `Bu abonelik için e-posta almayı durdurmak için lütfen şu sayfayı ziyaret edin:`;
		case `Or, visit your settings page to edit your subscriptions:`:
			return `Veya aboneliklerinizi düzenlemek için ayarlar sayfanızı ziyaret edin:`;
		case `post`:
			return `İleti`;
		case `Invalid email address`:
			return `Geçersiz e-posta adresi`;
		case `Additionally, you can %ssubscribe to an ATOM feed of matched posts%s, or %sread them online%s.`:
			return `Ek olarak, seçilen gönderiler için bir %sATOM feed aboneliği başlatabilir%s veya gönderileri %sburadan okuyabilirsiniz%s.`;
		case `No such post:`:
			return `Böyle bir gönderi yok:`;
		case `Post #%d of thread %s not found`:
			return `#%d numaralı gönderi %s numaralı konuda bulunamadı`;
		case `Jump to page:`:
			return `Sayfaya atla:`;
		case `Page`:
			return `Sayfa`;
		case `Go`:
			return `Git`;
		case `Thread overview`:
			return `Konuya genel bakış`;
		case `Thread not found`:
			return `Konu bulunamadı`;
		case `Permalink`:
			return `Kalıcı bağlantı`;
		case `Canonical link to this post. See "Canonical links" on the Help page for more information.`:
			return `Bu gönderiye kalıcı bağlantı. Daha fazla bilgi için Yardım sayfasındaki "Kalıcı bağlantılar" bölümüne bakınız.`;
		case `Reply`:
			return `Yanıtla`;
		case `Reply to this post`:
			return `Bu gönderiyi yanıtla`;
		case `Subscribe`:
			return `Abone ol`;
		case `Subscribe to this thread`:
			return `Bu konuya abone ol`;
		case `Flag`:
			return `Bildir`;
		case `Flag this post for moderator intervention`:
			return `Bu gönderiyi yönetici müdahalesi için işaretleyin`;
		case `Source`:
			return `Kaynak`;
		case `View this message's source code`:
			return `Bu mesajın kaynak kodunu görüntüle`;
		case `Moderate`:
			return `Yönet`;
		case `Perform moderation actions on this post`:
			return `Bu gönderi üzerinde denetim işlemleri gerçekleştirin`;
		case `%s's Gravatar profile`:
			return `%s kullanıcısının Gravatar profili`;
		case `Posted by %s`:
			return `Gönderen: %s`;
		case `in reply to`:
			return `Yanıtlanan: `;
		case `part`:
			return `Bölüm`;
		case `Posted in reply to`:
			return `Yanıtlanan: `;
		case `Attachments:`:
			return `Ekler:`;
		case `View in thread`:
			return `Konusu içinde görüntüle`;
		case `Replies to %s's post from %s`:
			return `%s tarafından gönderilen %s gönderisine yanıtlar`;
		case `Permanent link to this post`:
			return `Bu gönderiye kalıcı bağlantı`;
		case `%s's Gravatar profile"`:
			return `Gravatar profili (%s)"`;
		case `You seem to be posting using an unusual user-agent`:
			return `Garip bir kullanıcı programı (user-agent) kullanıyorsunuz`;
		case `Your subject contains a suspicious keyword or character sequence`:
			return `Konu başlığınız şüpheli bir anahtar kelime veya karakter dizisi içeriyor`;
		case `Your post contains a suspicious keyword or character sequence`:
			return `Gönderiniz şüpheli bir anahtar kelime veya karakter dizisi içeriyor`;
		case `Your top-level post is suspiciously short`:
			return `Konu başlığınız ve gönderiniz şüpheli derecede kısa`;
		case `Your post looks like spam (%d%% spamicity)`:
			return `Gönderiniz spam gibi görünüyor (%d%% spamicity)`;
		case `from the future`:
			return `gelecekten`;
		case `just now`:
			return `az önce`;
		case `%d %s ago`:
			return `%d %s önce`;
		case `basic`:
			return `Temel`;
		case `threaded`:
			return `Gönderi listesi`;
		case `horizontal-split`:
			return `Yatay bölünmüş`;
		case `vertical-split`:
			return `Dikey bölünmüş`;
		case `Unknown view mode`:
			return `Bilinmeyen görünüm`;
		case `You have an %sunsent draft message from %s%s.`:
			return `%s%s tarihinden kalmış bir taslak mesajınız%s var.`;
		case `This message is awaiting moderation.`:
			return `Bu mesaj bir yönetici tarafından denetlenmeyi bekliyor.`;
		case `This message has already been posted.`:
			return `Bu mesaj zaten gönderilmiş.`;
		case `Can't post to archive`:
			return `Arşive gönderilemiyor`;
		case `Note: you are posting to a mailing list.`:
			return `Not: Bir posta listesine gönderiyorsunuz.`;
		case `Your message will not go through unless you %ssubscribe to the mailing list%s first.`:
			return `%sPosta listesine abone olmadığınız%s sürece mesajınız gönderilmeyecek.`;
		case `You must then use the same email address when posting here as the one you used to subscribe to the list.`:
			return `Buradan gönderirken listeye abone olmak için kullandığınız e-posta adresini kullanmanız gerekir.`;
		case `If you do not want to receive mailing list mail, you can disable mail delivery at the above link.`:
			return `Posta listesi gönderisi almak istemiyorsanız, yukarıdaki bağlantıdan posta teslimini devre dışı bırakabilirsiniz.`;
		case `Warning: the post you are replying to is from`:
			return `Uyarı: yanıtladığınız gönderi eski:`;
		case `Posting to`:
			return ``;
		case `unknown post`:
			return `bilinmeyen gönderi`;
		case `Your name:`:
			return `Adınız:`;
		case `Your email address`:
			return `E-posta adresiniz`;
		case `Subject:`:
			return `Konu:`;
		case `Message:`:
			return `İleti:`;
		case `Save and preview`:
			return `Kaydet ve önizle`;
		case `Send`:
			return `Gönder`;
		case `Discard draft`:
			return `Taslağı sil`;
		case `This message has already been sent.`:
			return `Bu mesaj zaten gönderilmiş.`;
		case `Automatic fix applied.`:
			return `Otomatik düzeltme uygulandı.`;
		case `Undo`:
			return `Geri al`;
		case `Sorry, a problem occurred while attempting to fix your post`:
			return `Üzgünüz, gönderinizi düzeltmeye çalışırken bir sorun oluştu`;
		case `Undo information not found.`:
			return `Geri alma bilgisi bulunamadı.`;
		case `Automatic fix undone.`:
			return `Otomatik düzeltme geri alındı.`;
		case `Warning:`:
			return `Uyarı:`;
		case `Ignore`:
			return `Göz ardı et`;
		case `Explain`:
			return `Açıkla`;
		case `Fix it for me`:
			return `Benim için düzelt`;
		case `You've attempted to post %d times in the past %s. Please wait a little bit before trying again.`:
			return `Geçmiş %2$s süresi içinde %1$d kez göndermeye çalıştınız. Tekrar denemeden önce lütfen biraz bekleyin.`;
		case `You've attempted to post %d times in the past %s. Please solve a CAPTCHA to continue.`:
			return `Geçmiş %2$s süresi içinde %1$d kez göndermeye çalıştınız. Devam etmek için lütfen bir CAPTCHA çözünüz.`;
		case `Your message has been saved, and will be posted after being approved by a moderator.`:
			return `Mesajınız kaydedildi; bir yönetici tarafından onaylandıktan sonra gönderilecek.`;
		case `Unknown action`:
			return `Bilinmeyen eylem`;
		case `Posting status`:
			return `Gönderi durumu`;
		case `Validating...`:
			return `Doğrulanıyor...`;
		case `Verifying reCAPTCHA...`:
			return `reCAPTCHA doğrulanıyor ...`;
		case `Connecting to server...`:
			return `Sunucuya baglanıyor...`;
		case `Sending message to server...`:
			return `Sunucuya mesaj gönderiliyor...`;
		case `Message sent.`:
			return `Mesaj gönderildi.`;
		case `Waiting for message announcement...`:
			return `Mesaj duyurusu bekleniyor...`;
		case `Message posted! Redirecting...`:
			return `Mesaj gönderildi! Yönlendiriliyor...`;
		case `%s. Please solve a CAPTCHA to continue.`:
			return `%s. Devam etmek için lütfen bir CAPTCHA çözünüz.`;
		case `Spam check error:`:
			return `Spam denetimi hatası:`;
		case `Try clearing your browser's cookies. Create an account to avoid repeated incidents.`:
			return `Tarayıcınızın çerezlerini temizlemeyi deneyin. Bu gibi tekrarlardan kaçınmak için bir hesap oluşturun.`;
		case `Malformed Base64 in read post history cookie.`:
			return `Okuma geçmişi çerezinde hatalı Base64.`;
		case `Malformed deflated data in read post history cookie`:
			return `Okuma geçmişi çerezinde hatalı sıkıştırılmış veri`;
		case `Please enter a username`:
			return `Lütfen bir kullanıcı adı giriniz`;
		case `Username too long`:
			return `Kullanıcı adı çok uzun`;
		case `Password too long`:
			return `Şifre çok uzun`;
		case `Already logged in`:
			return `Zaten giriş yapılmış`;
		case `Already registered`:
			return `Zaten kayıtlı`;
		case `Can't edit this message. It has already been sent.`:
			return `Bu mesajı düzenleyemezsiniz. Zaten gönderildi.`;
		case `Can't edit this message. It has already been submitted for moderation.`:
			return `Bu mesajı düzenleyemezsiniz. Zaten denetim için gönderildi.`;
		case `StopForumSpam API error:`:
			return `StopForumSpam API hatası:`;
		case `StopForumSpam thinks you may be a spammer (%s last seen: %s, frequency: %s)`:
			return `StopForumSpam, spam yapan birisi olduğunuzdan şüpheleniyor (%s son görülme: %s, sıklık: %s)`;
		case `Log in`:
			return `Oturum aç`;
		case `Username:`:
			return `Kullanıcı adı:`;
		case `Password:`:
			return `Şifre:`;
		case `Remember me`:
			return `Beni Hatırla`;
		case `Register`:
			return `Kayıt ol`;
		case `to keep your preferences<br>and read post history on the server.`:
			return `(Ayarlarınızı ve gönderi geçmişinizi sunucuda saklamak için.)`;
		case `Confirm:`:
			return `Onaylayın:`;
		case `Please pick your password carefully.`:
			return `Lütfen şifrenizi dikkatlice seçin.`;
		case `There are no password recovery options.`:
			return `Şifre kurtarma seçeneği yoktur.`;
		case `Passwords do not match`:
			return `Şifre uyuşmuyor`;
		case `First`:
			return `İlk`;
		case `Prev`:
			return `Önceki`;
		case `Next`:
			return `Sonraki`;
		case `Last`:
			return `Son`;
		case `Advanced Search`:
			return `Gelişmiş Arama`;
		case `Find posts with...`:
			return `Aşağıdakilere uyan gönderileri bulur.`;
		case `all these words:`:
			return `Şu kelimelerin hepsi:`;
		case `this exact phrase:`:
			return `Tam olarak şu söz dizisi:`;
		case `none of these words:`:
			return `Şu kelimelerin hiçbiri:`;
		case `posted in the group:`:
			return `Gönderildiği grup:`;
		case `posted by:`:
			return `Gönderenin adı:`;
		case `posted by (email):`:
			return `Gönderenin e-posta'sı:`;
		case `in threads titled:`:
			return `Konu başlığı:`;
		case `containing:`:
			return `İçeriğinde geçen:`;
		case `posted between:`:
			return `Tarih aralığı:`;
		case `yyyy-mm-dd`:
			return `yyyy-aa-gg`;
		case `posted as new thread:`:
			return `Konunun ilk mesajı:`;
		case `Advanced search`:
			return `Gelişmiş ara`;
		case `Search`:
			return `Ara`;
		case `Invalid date: %s (%s)`:
			return `Geçersiz tarih: %s (%s)`;
		case `Start date must be before end date`:
			return `Başlangıç ​​tarihi bitiş tarihinden önce olmalıdır`;
		case `Invalid page number`:
			return `Geçersiz sayfa numarası`;
		case `Your search -`:
			return `Aramanız -`;
		case `- did not match any forum posts.`:
			return `- hiçbir forum gönderisiyle eşleşmedi.`;
		case `View this post`:
			return `Bu gönderiyi görüntüle`;
		case `Invalid path`:
			return `Geçersiz yol`;
		case `Legacy redirect - unsupported feature`:
			return `Eski yönlendirme - desteklenmeyen özellik`;
		case `Legacy redirect - article not found`:
			return `Eski yönlendirme - gönderi bulunamadı`;
		case `Legacy redirect - ambiguous artnum (group parameter missing)`:
			return `Eski yönlendirme - belirsiz artnum (grup parametresi eksik)`;
		case `No group specified`:
			return `Grup belirtilmedi`;
		case `(page %d)`:
			return `(sayfa %d)`;
		case `Unknown group`:
			return `Bilinmeyen grup`;
		case `%s group index`:
			return `%s grup dizini`;
		case `New posts on`:
			return `Yeni gönderiler:`;
		case `New threads on`:
			return `Yeni konular:`;
		case `No thread specified`:
			return `Konu belirtilmedi`;
		case `Viewing thread in basic view mode – click a post's title to open it in %s view mode`:
			return `Konu temel görünüm ile görüntüleniyor - %s olarak görüntülemek için bir konuya tıklayın`;
		case `No post specified`:
			return `Gönderi belirtilmedi`;
		case `(view single post)`:
			return `(tek gönderiyi görüntüle)`;
		case `Invalid URL`:
			return `Geçersiz URL`;
		case `No such group`:
			return `Böyle bir grup yok`;
		case `Posting to %s`:
			return `Alıcı: %s`;
		case `New thread`:
			return `Yeni konu`;
		case `Replying to "%s"`:
			return `Yanıtlanan: "%s"`;
		case `Post reply`:
			return `Yanıt gönder`;
		case `Posting`:
			return `Gönderi`;
		case `No post ID specified`:
			return `Gönderi kimliği belirtilmemiş`;
		case `Composing message`:
			return `Mesaj oluşturma`;
		case `Please log in to do that`:
			return `Lütfen giriş yapınız`;
		case `Subscribe to thread`:
			return `Konuya abone ol`;
		case `No subscription specified`:
			return `Abonelik belirtilmemiş`;
		case `View subscription`:
			return `Aboneliği görüntüle`;
		case `Unsubscribe`:
			return `Aboneliği iptal et`;
		case `You are not a moderator`:
			return `Yönetici değilsiniz`;
		case `Moderating post "%s"`:
			return `"%s" gönderisi denetleniyor`;
		case `Moderate post`:
			return `Gönderiyi denetle`;
		case `You can't flag posts`:
			return `Gönderileri işaretleyemezsiniz`;
		case `Flag "%s" by %s`:
			return `%2$s tarafından gönderilen "%1$s" gönderisini işaretle`;
		case `Flag post`:
			return `Gönderiyi işaretle`;
		case `You can't approve moderated drafts`:
			return `Denetlenmiş olan taslakları siz onaylayamazsınız`;
		case `Approving moderated draft`:
			return `Denetlenmiş olan taslak onaylanıyor`;
		case `Registration`:
			return `Kayıt`;
		case `Login error`:
			return `Giriş hatası`;
		case `Registration error`:
			return `Kayıt Hatası`;
		case `Account`:
			return `Hesap`;
		case `Change Password`:
			return `Şifre değiştir`;
		case `Export Data`:
			return `Dışa Aktar`;
		case `Delete Account`:
			return `Hesabı sil`;
		case `Help`:
			return `Yardım`;
		case `Forum activity summary`:
			return `Forum etkinliği özeti`;
		case `Feed type not specified`:
			return `Feed türü belirtilmedi`;
		case `Unknown feed type`:
			return `Bilinmeyen feed türü`;
		case `hours parameter exceeds limit`:
			return `hours parametresi sınırı aşıyor`;
		case `Not Found`:
			return `Bulunamadı`;
		case `Error`:
			return `Hata`;
		case `Index`:
			return `Dizin`;
		case `Log out`:
			return `Çıkış Yap`;
		case `Draft discarded.`:
			return `Taslak silindi.`;
		case `Settings saved.`:
			return `Ayarlar kaydedildi.`;
		case `Warning: cookie size approaching RFC 2109 limit.`:
			return `Uyarı: çerez boyutu RFC 2109 sınırına yaklaşıyor.`;
		case `Please consider %screating an account%s to avoid losing your read post history.`:
			return `Okuma geçmişinizi kaybetmemek için lütfen %shesap açtırın%s.`;
		case `Forums`:
			return `Forumlarda`;
		case `%s group`:
			return `%s grubunda`;
		case `View subscription:`:
			return ``;
		case `It looks like there's nothing here! No posts matched this subscription so far.`:
			return `Görünüşe göre burada hiçbir şey yok! Henüz bu abonelikle eşleşen gönderi yok.`;
		case `This subscription has been deactivated.`:
			return `Bu abonelik devre dışı bırakıldı.`;
		case `If you did not intend to do this, you can reactivate the subscription's actions on your %ssettings page%s.`:
			return `Bunu yapmak istemediyseniz, aboneliğin eylemlerini %sayarlar sayfanızda%s yeniden etkinleştirebilirsiniz.`;
		case `Hint`:
			return `İpucu`;
		case "Is the CAPTCHA too hard?\nRefresh the page to get a different question,\nor ask in the %s#d IRC channel on Freenode%s.":
			return `CAPTCHA çok mu zor?\nFarklı bir soru almak için sayfayı yenileyin\nveya yanıtını %sFreenode üzerindeki #d IRC kanalında%s sorun.`;
		case `Unknown or expired CAPTCHA challenge`:
			return `Bilinmeyen veya süresi dolmuş CAPTCHA testi`;
		case `The answer is incorrect`:
			return `Yanıt yanlış`;
		case `Akismet thinks your post looks like spam`:
			return `Akismet, gönderinizin spam gibi göründüğünü düşünüyor`;
		case `Akismet error:`:
			return `Akismet hatası:`;
		case `Latest announcements`:
			return `Son duyurular`;
		case `Active discussions`:
			return `Aktif konu`;
		case `ProjectHoneyPot thinks you may be a spammer (%s last seen: %d days ago, threat score: %d/255, type: %s)`:
			return `ProjectHoneyPot, spam yapan birisi olduğunuzdan şüpheleniyor (%s son görülme: %d gün önce, tehdit puanı: %d/255, tür: %s)`;
		case `From`:
			return `Gönderen`;
		case `Date`:
			return `Tarih`;
		case `In reply to`:
			return `Yanıtlanan:`;
		case `Attachments`:
			return `Ekler`;
		case `Parent post is not quoted.`:
			return `Alıntı yapılmamış.`;
		case `When replying to someone's post, you should provide some context for your replies by quoting the revelant parts of their post.`:
			return `Bir gönderiyi yanıtlarken, gönderinin ilgili bölümlerini alıntılayarak yanıtınızın açıklayıcı olmasını sağlamalısınız.`;
		case `Depending on the software (or its configuration) used to read your message, it may not be obvious which post you're replying to.`:
			return `Mesajınızın alıcı tarafında okunduğu programa (veya onun ayarlarına) bağlı olarak, hangi gönderiyi yanıtladığınız belli olmayabilir.`;
		case `Thus, when writing a reply, don't delete all quoted text: instead, leave just enough to provide context for your reply.`:
			return `Bu nedenle, bir yanıt yazarken, alıntılanan tüm metni silmek yerine, yanıtınızın anlamlı olmasına yetecek kadar alıntı bırakın.`;
		case `You can also insert your replies inline (interleaved with quoted text) to address specific parts of the parent post.`:
			return `Gönderinin belirli bölümlerine yanıt vermek için yanıtlarınızı alıntılanmış metinle iç içe olarak da ekleyebilirsiniz.`;
		case `You are quoting a post other than the parent.`:
			return `Bir öncekinden farklı bir gönderiyi alıntılıyorsunuz.`;
		case `When replying a message, the message you are replying to is referenced in the post's headers.`:
			return `Yanıtladığınız mesaj yazının başlık alanlarında belirtilir.`;
		case `Depending on the software (or its configuration) used to read your message, your message may be displayed below its parent post.`:
			return `Mesajınızın alıcı tarafında okunduğu programa (veya onun ayarlarına) bağlı olarak, mesajınız yanıtlanmakta olan gönderinin altında görüntülenebilir.`;
		case `If your message contains a reply to a different post, following the conversation may become somewhat confusing.`:
			return `Mesajınız farklı bir gönderiye yanıt içerdiğinde konunun anlaşılırlığı güçleşebilir.`;
		case `Thus, make sure to click the "Reply" link on the actual post you're replying to, and quote the parent post for context.`:
			return `Bu nedenle, lütfen yanıtlamakta olduğunuz gönderinin "Yanıtla" bağlantısını tıkladığınızdan ve onu alıntıladığınızdan emin olun.`;
		case `Parent post is not indicated.`:
			return `Yanıtlanan gönderi belirtilmemiş.`;
		case `When quoting someone's post, you should leave the "On (date), (author) wrote:" line.`:
			return `Bir gönderiyi alıntılarken, lütfen yanıtlanan gönderinin tarih ve yazar bilgisini taşıyan satırı silmeyin.`;
		case `Thus, this line provides important context for your replies regarding the structure of the conversation.`:
			return `O bilgi, sohbetin anlaşılmasına yardımcı olur.`;
		case `You are quoting multiple posts.`:
			return `Birden fazla gönderiden alıntı yapıyorsunuz.`;
		case `Thus, you should avoid replying to multiple posts in one reply.`:
			return `Tek bir yanıtta birden fazla gönderiye yanıt vermekten kaçınmalısınız.`;
		case `If applicable, you should split your message into several, each as a reply to its corresponding parent post.`:
			return `Mümkünse, yanıtlanmakta olan her mesaj için farklı yanıt yazmalısınız.`;
		case `You are top-posting.`:
			return `Yanıtınızı asıl gönderinin üst tarafına yazıyorsunuz.`;
		case `When replying a message, it is generally preferred to add your reply under the quoted parent text.`:
			return `Genel tercih, yanıtınızı alıntılanan metnin altına yazmanızdır.`;
		case `Depending on the software (or its configuration) used to read your message, your message may not be displayed below its parent post.`:
			return `Mesajınızın alıcı tarafında okunduğu programa (veya onun ayarlarına) bağlı olarak, mesajınız yanıtlanmakta olan gönderinin altında görüntülenmiyor olabilir.`;
		case `In such cases, readers would need to first read the quoted text below your reply for context.`:
			return `Öyle ise, okuyucular önce yanıtınızın altındaki alıntıyı okumak zorunda kalırlar.`;
		case `Thus, you should add your reply below the quoted text (or reply to individual paragraphs inline), rather than above it.`:
			return `Bu nedenle, yanıtınızı alıntıladığınız metnin altına (veya birden fazla bölüm halinde iç içe) yazmalısınız.`;
		case `You are overquoting.`:
			return `Çok fazla alıntı yapmışsınız.`;
		case `The ratio between quoted and added text is vastly disproportional.`:
			return `Alıntılanan ve eklenen metin çok orantısız.`;
		case `Quoting should be limited to the amount necessary to provide context for your replies.`:
			return `Alıntı, yanıtınıza anlam katmaya yetecek kadar olmalıdır.`;
		case `Quoting posts in their entirety is thus rarely necessary, and is a waste of vertical space.`:
			return `Bu nedenle, metnin tamamını alıntılamak nadiren gereklidir ve alan israfıdır.`;
		case `Please trim the quoted text to just the relevant parts you're addressing in your reply, or add more content to your post.`:
			return `Lütfen alıntılanan metni yanıtınızda ele aldığınız kısımlarla ilgili olarak kısaltın veya gönderinize daha fazla içerik ekleyin.`;
		case `Don't use URL shorteners.`:
			return `URL kısaltıcıları kullanmayınız.`;
		case `URL shortening services, such as TinyURL, are useful in cases where space is at a premium, e.g. in IRC or Twitter messages.`:
			return `TinyURL gibi URL kısaltma hizmetleri, alanın kısıtlı olduğu IRC veya Twitter mesajları gibi ortamlarda yararlıdır.`;
		case `In other circumstances, however, they provide little benefit, and have the significant disadvantage of being opaque:`:
			return `Ancak diğer durumlarda çok az fayda sağlarlar ve bağlantının anlaşılırlığını düşürürler:`;
		case `readers can only guess where the link will lead to before they click it.`:
			return `okuyucular, tıklanan bağlantının nereye götüreceği konusunda tahminde bulunamazlar.`;
		case `Additionally, URL shortening services come and go - your link may work today, but might not in a year or two.`:
			return `Ek olarak, URL kısaltma hizmetleri kalıcı değillerdir - bugün işleyen bir bağlantı bir iki yıl içinde yitirilmiş olabilir.`;
		case `Thus, do not use URL shorteners when posting messages online - post the full link instead, even if it seems exceedingly long.`:
			return `Bu nedenle, gönderilerinizde URL kısaltmaları kullanmak yerine, aşırı uzun görünüyor olsa bile tam bağlantıyı verin.`;
		case `If it is too long to be inserted inline, add it as a footnote instead.`:
			return `Satır içi için fazla uzun olduğunu düşündüğünüzde mesajınıza dipnot olarak ekleyebilirsiniz.`;
		case `Could not expand URL:`:
			return `URL genişletilemedi:`;
		case `Don't put links in the subject.`:
			return `Konu satırına bağlantı koymayın.`;
		case `Links in message subjects are usually not clickable.`:
			return `Konu satırlarındaki bağlantılar genellikle tıklanabilir değildir.`;
		case `Please move the link in the message body instead.`:
			return `Lütfen bağlantıyı mesaj içine taşıyın.`;
		case `Avoid replying to very old threads.`:
			return `Çok eski konuları yanıtlamaktan kaçının.`;
		case `The thread / post you are replying to is very old.`:
			return `Yanıtladığınız konu veya gönderi çok eski.`;
		case `Consider creating a new thread instead of replying to an existing one.`:
			return `Mevcut konuyu yanıtlamak yerine yeni bir konu başlatmayı düşünün.`;
		case `BlogSpam.net thinks your post looks like spam:`:
			return `BlogSpam.net, gönderinizin spam gibi göründüğünü düşünüyor:`;
		case `BlogSpam.net error:`:
			return `BlogSpam.net hatası:`;
		case `BlogSpam.net unexpected response:`:
			return `BlogSpam.net beklenmeyen yanıt:`;
		case `Perform which moderation actions on this post?`:
			return `Hangi denetim işlemleri uygulansın?`;
		case `Delete local cached copy of this post from DFeed's database`:
			return `Bu gönderinin yerel kopyasını DFeed veritabanından sil`;
		case `Ban poster (place future posts in moderation queue)`:
			return `Göndericiyi yasakla (gelecekteki gönderileri de denetlensin)`;
		case `Delete source copy from %-(%s/%)`:
			return `%-(%s/%) kaynağındaki asıl kopyasını sil`;
		case `Reason:`:
			return `Nedeni:`;
		case `It looks like you've already flagged this post.`:
			return `Görünüşe göre bu gönderiyi zaten işaretlemişsiniz.`;
		case `Would you like to %sunflag it%s?`:
			return `%sİşaretini kaldırmak%s ister misiniz?`;
		case `Are you sure you want to flag this post?`:
			return `Bu gönderiyi işaretlemek istediğinizden emin misiniz?`;
		case `You can't flag posts!`:
			return `Gönderileri işaretleyemezsiniz!`;
		case `You can't flag this post!`:
			return `Bu gönderiyi işaretleyemezsiniz!`;
		case `You've already flagged this post.`:
			return `Bu gönderiyi zaten işaretlediniz.`;
		case `Post flagged.`:
			return `Gönderi işaretlendi.`;
		case `Return to post`:
			return `Gönderiye dön`;
		case `It looks like you've already unflagged this post.`:
			return `Görünüşe göre bu gönderinin işaretini zaten kaldırmışsınız.`;
		case `Would you like to %sflag it%s?`:
			return `%sİşaretlemek%s ister misiniz?`;
		case `Are you sure you want to unflag this post?`:
			return `Bu gönderinin işaretini kaldırmak istediğinizden emin misiniz?`;
		case `Unflag`:
			return `İşareti kaldır`;
		case `You've already unflagged this post.`:
			return `Bu gönderinin işaretini zaten kaldırdınız.`;
		case `Post unflagged.`:
			return `İşaret kaldırıldı.`;
		case `You can view it here.`:
			return `Buradan görüntüleyebilirsiniz.`;
		case `This is not a post in need of moderation. Its status is currently:`:
			return `Bu, denetlenmesi gereken bir gönderi değil. Şu andaki durumu:`;
		case `Are you sure you want to approve this post?`:
			return `Bu gönderiyi onaylamak istediğinizden emin misiniz?`;
		case `Approve`:
			return `Onayla`;
		case `Post approved!`:
			return `Gönderi onaylandı!`;
		case `View posting`:
			return `Gönderiyi görüntüle`;
		default:
			assert(false, "Unknown Turkish string: " ~ s);
	}
}

private string pluralOf(string unit)
{
	switch (unit)
	{
		case "second":
      return "saniye";

		case "minute":
      return "dakika";

		case "hour":
      return "saat";

		case "day":
      return "gün";

		case "week":
      return "hafta";

		case "month":
      return "ay";

		case "year":
      return "yıl";

		case "thread":
      return "konu";

		case "post":
      return "gönderi";

		case "forum post":
      return "forum gönderisi";

		case "subscription":
      // This seems to be used only in the `No new posts matching your %s%s%s.` string where it happens to be the first
      // word in Turkish, so we use it capitalized for now.
      return "Abonelikleriniz";

		case "unread post":
      return "okunmamış gönderi";

		case "registered user":
      return "kayıtlı kullanıcı";

		case "visit":
      // This seems to be used only in the `You have read a total of %s %s during your %s.` string where it happens to
      // be the first word in Turkish, so we use it capitalized for now.
      return "Ziyaretiniz";

		case "new reply":
      return "yeni yanıt";

		case "user has created":
      return "kullanıcı tarafından";

		default:
			assert(false, "Unknown unit: " ~ unit);
	}
}

string plural(string unit)(long amount)
{
	// There are no plural forms of nouns in Turkish.
	return pluralOf(unit);
}

const WeekdayShortNames = ["Paz", "Pzt", "Sal", "Çar", "Per", "Cum", "Cmt"];
const WeekdayLongNames = ["Pazar", "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi"];
const MonthShortNames = ["Oca", "Şub", "Mar", "Nis", "May", "Haz", "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara"];
const MonthLongNames = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran", "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"];
