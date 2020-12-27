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

string translate(string s)
{
	switch (s)
	{
		case `Please enter a name`:
			return `Lütfen bir isim giriniz`;
		case `Please enter an email address`:
			return `Lütfen bir e-posta adresi giriniz`;
		case `Please enter a message subject`:
			return `Lütfen bir mesaj konusu girin`;
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
			return `Gönderi devre dışı bırakıldı`;
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
			return `için %d %s %sgönderiniz var%s.`;
		case `No new %sreplies%s to your posts.`:
			return `Gönderilerinize yeni %syanıt yok%s.`;
		case `You have %d %s matching your %s%s subscription%s (%s).`:
			return `%3$s%4$s aboneliğinizle eşleşen %1$d %2$s var %5$s (%6$s).`;
		case `No new posts matching your %s%s%s.`:
			return `%s%s%s ile eşleşen yeni gönderi yok.`;
		case `If you %screate an account%s, you can track replies to %syour posts%s.`:
			return `%s hesabına %s bakarsanız, %s gönderilerinize %s verilen yanıtları izleyebilirsiniz.`;
		case `You can read and post on this forum without %screating an account%s, but doing so offers %sa few benefits%s.`:
			return `Bu forumu %s hesap açmadan okuyabilir ve yayınlayabilirsiniz%s, ancak bunu yapmak %sa birkaç avantaj %s sağlar.`;
		case `%d %s %-(%s and %)`:
			return `%d %s%-(%s ve%)`;
		case `No new forum activity`:
			return `Yeni forum etkinliği yok`;
		case `since your last visit (%s).`:
			return `son ziyaretinizden beri (%s).`;
		case `in the last 24 hours.`:
			return `son 24 saat içinde.`;
		case `There are %s %s, %s %s, and %s %s on this forum.`:
			return `Bu forumda %s %s, %s %s ve %s %s var.`;
		case `You have read a total of %s %s during your %s.`:
			return `%s sırasında toplam %s %s okudunuz.`;
		case `Random tip:`:
			return `Rastgele ipucu:`;
		case `This forum has several different <a href="/help#view-modes">view modes</a>. Try them to find one you like best. You can change the view mode in the <a href="/settings">settings</a>.`:
			return `Bu forumun birkaç farklı <a href="/help#view-modes"> görünüm modu </a> vardır. En sevdiğiniz birini bulmaya çalışın. Görünüm modunu <a href="/settings"> ayarlardan </a> değiştirebilirsiniz.`;
		case `This forum supports <a href="/help#keynav">keyboard shortcuts</a>. Press <kbd>?</kbd> to view them.`:
			return `Bu forum <a href="/help#keynav"> klavye kısayollarını </a> destekler. Görüntülemek için <kbd>? </kbd> tuşuna basın.`;
		case `You can focus a message with <kbd>j</kbd>/<kbd>k</kbd> and press <kbd>u</kbd> to mark it as unread, to remind you to read it later.`:
			return `Bir mesajı <kbd> j </kbd> / <kbd> k </kbd> ile odaklayabilir ve <kbd> u </kbd> tuşuna basarak onu daha sonra okumanızı hatırlatmak için okunmadı olarak işaretleyebilirsiniz.`;
		case `The <a href="/help#avatars">avatars on this forum</a> are provided by Gravatar, which allows associating a global avatar with an email address.`:
			return `<a href="/help#avatars"> Bu forumdaki avatarlar </a>, global bir avatarın bir e-posta adresiyle ilişkilendirilmesine izin veren Gravatar tarafından sağlanmaktadır.`;
		case `This forum remembers your read post history on a per-post basis. If you are logged in, the post history is saved on the server, and in a compressed cookie otherwise.`:
			return `Bu forum, yazı başına temelde okunduğunuz gönderi geçmişinizi hatırlar. Giriş yaptıysanız, gönderi geçmişi sunucuya, aksi takdirde sıkıştırılmış bir tanımlama bilgisine kaydedilir.`;
		case `Much of this forum's content is also available via classic mailing lists or NNTP - see the "Also via" column on the forum index.`:
			return `Bu forumun içeriğinin çoğu, klasik posta listeleri veya NNTP aracılığıyla da mevcuttur - forum dizinindeki "Ayrıca şu yolla" sütununa bakın.`;
		case `If you create a Gravatar profile with the email address you post with, it will be accessible when clicking your avatar.`:
			return `Gönderdiğiniz e-posta adresiyle bir Gravatar profili oluşturursanız, avatarınıza tıkladığınızda erişilebilir olacaktır.`;
		case `To subscribe to a thread, click the "Subscribe" link on that thread's first post. You need to be logged in to create subscriptions.`:
			return `Bir ileti dizisine abone olmak için, o ileti dizisinin ilk gönderisindeki "Abone Ol" bağlantısını tıklayın. Abonelik oluşturmak için giriş yapmalısınız.`;
		case `To search the forum, use the search widget at the top, or you can visit <a href="/search">the search page</a> directly.`:
			return `Forumda arama yapmak için üstteki arama widget'ını kullanın veya doğrudan <a href="/search"> arama sayfasını </a> ziyaret edebilirsiniz.`;
		case `This forum is open-source! Read or fork the code <a href="https://github.com/CyberShadow/DFeed">on GitHub</a>.`:
			return `Bu forum açık kaynaklıdır! <a href="https://github.com/CyberShadow/DFeed"> GitHub'da </a> kodu okuyun veya çatallayın.`;
		case `If you encounter a bug or need a missing feature, you can <a href="https://github.com/CyberShadow/DFeed/issues">create an issue on GitHub</a>.`:
			return `Bir hatayla karşılaşırsanız veya eksik bir özelliğe ihtiyaç duyarsanız, <a href="https://github.com/CyberShadow/DFeed/issues"> GitHub'da bir sorun oluşturabilirsiniz </a>.`;
		case `Group`:
			return `Grup`;
		case `Last Post`:
			return `Son Posta`;
		case `Threads`:
			return `İş Parçacığı`;
		case `Posts`:
			return `Gönderiler`;
		case `Also via`:
			return `Ayrıca aracılığıyla`;
		case `Create thread`:
			return `IP oluşurmak`;
		case `Invalid page`:
			return `Geçersiz sayfa`;
		case `by`:
			return `tarafından`;
		case `Thread / Thread Starter`:
			return `Konu / Konuyu Başlatan`;
		case `Replies`:
			return `Cevaplar`;
		case `Loading...`:
			return `Yükleniyor...`;
		case `Sorry, this view requires JavaScript.`:
			return `Üzgünüz, bu görünüm JavaScript gerektirmektedir.`;
		case `Unknown group:`:
			return `Bilinmeyen grup:`;
		case `Can't find thread's page`:
			return `Konunun sayfasını bulamıyorum`;
		case `Can't find post's page`:
			return `Gönderinin sayfasını bulamıyorum`;
		case `The specified resource cannot be found on this server.`:
			return `Belirtilen kaynak bu sunucuda bulunamıyor.`;
		case `XSRF secret verification failed. Are your cookies enabled?`:
			return `XSRF gizli doğrulaması başarısız oldu. Çerezleriniz etkinleştirildi mi?`;
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
			return `Görünüm modu:`;
		case `Enable keyboard shortcuts`:
			return `Klavye kısayollarını etkinleştirin`;
		case `Automatically open messages after selecting them.`:
			return `Mesajları seçtikten sonra otomatik olarak açın.`;
		case `Applicable to threaded, horizontal-split and vertical-split view modes.`:
			return `Dişli, yatay bölünmüş ve dikey bölünmüş görünüm modları için geçerlidir.`;
		case `Focus follows message`:
			return `Odak mesajı takip eder`;
		case `Save`:
			return `Kayıt etmek`;
		case `Cancel`:
			return `İptal etmek`;
		case `Subscriptions`:
			return `Abonelikler`;
		case `Subscription`:
			return `Abonelik`;
		case `Actions`:
			return `Hareketler`;
		case `View posts`:
			return `Yayınları görüntüle`;
		case `Get ATOM feed`:
			return `ATOM beslemesini alın`;
		case `Edit`:
			return `Düzenle`;
		case `Delete`:
			return `Sil`;
		case `You have no subscriptions.`:
			return `Aboneliğiniz yok.`;
		case `Create new content alert subscription`:
			return `Yeni içerik uyarısı aboneliği oluşturun`;
		case `Please %slog in%s to manage your subscriptions and account settings.`:
			return `Aboneliklerinizi ve hesap ayarlarınızı yönetmek için lütfen %s içinde %slog yapın.`;
		case `Account settings`:
			return `Hesap ayarları`;
		case `Change the password used to log in to this account.`:
			return `Bu hesapta oturum açmak için kullanılan parolayı değiştirin.`;
		case `Change password`:
			return `Şifre değiştir`;
		case `Download a file containing all data tied to this account.`:
			return `Bu hesaba bağlı tüm verileri içeren bir dosya indirin.`;
		case `Export data`:
			return `Verileri dışa aktar`;
		case `Permanently delete this account.`:
			return `Bu hesabı kalıcı olarak silin.`;
		case `Delete account`:
			return `Hesabı sil`;
		case `Edit subscription`:
			return `Aboneliği düzenleyin`;
		case `Condition`:
			return `Durum`;
		case `This action is only meaningful for logged-in users.`:
			return `Bu işlem yalnızca giriş yapmış kullanıcılar için anlamlıdır.`;
		case `Here you can change the password used to log in to this %s account.`:
			return `Burada, bu %s hesabına giriş yapmak için kullanılan şifreyi değiştirebilirsiniz.`;
		case `Please pick your new password carefully, as there are no password recovery options.`:
			return `Şifre kurtarma seçeneği olmadığından, lütfen yeni şifrenizi dikkatlice seçin.`;
		case `Current password:`:
			return `Şimdiki Şifre:`;
		case `New password:`:
			return `Yeni Şifre:`;
		case `New password (confirm):`:
			return `Yeni şifre (onaylayın):`;
		case `XSRF secret verification failed`:
			return `XSRF gizli doğrulaması başarısız oldu`;
		case `The current password you entered is incorrect`:
			return `Girdiğiniz mevcut şifre yanlış`;
		case `New passwords do not match`:
			return `yeni şifreler uyuşmuyor`;
		case `Password successfully changed.`:
			return `Şifre başarıyla değiştirildi.`;
		case `Export account data`:
			return `Hesap verilerini dışa aktar`;
		case `Here you can export the information regarding your account from the %s database.`:
			return `Burada hesabınızla ilgili bilgileri %s veritabanından dışa aktarabilirsiniz.`;
		case `Export`:
			return `İhracat`;
		case `Here you can permanently delete your %s account and associated data from the database.`:
			return `Burada %s hesabınızı ve ilişkili verileri veritabanından kalıcı olarak silebilirsiniz.`;
		case `After deletion, the account username will become available for registration again.`:
			return `Silme işleminden sonra, hesap kullanıcı adı tekrar kayıt için uygun hale gelecektir.`;
		case `To confirm deletion, please enter your account username and password.`:
			return `Silme işlemini onaylamak için lütfen hesap kullanıcı adınızı ve şifrenizi girin.`;
		case `Account username:`:
			return `Hesap kullanıcı adı:`;
		case `Account password:`:
			return `Hesap şifresi:`;
		case `Delete this account`:
			return `Bu hesabı silin`;
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
			return `Son Gönderiler`;
		case `%s subscription (%s)`:
			return `%s aboneliği (%s)`;
		case `No such subscription`:
			return `Böyle bir abonelik yok`;
		case `Not logged in`:
			return `Giriş yapmadınız`;
		case `No such user subscription`:
			return `Böyle bir kullanıcı aboneliği yok`;
		case `reply`:
			return `cevap`;
		case `Replies to your posts`:
			return `Gönderilerinize verilen yanıtlar`;
		case `%s replied to your post in the thread "%s"`:
			return `%s, " %s" başlığındaki yayınınıza yanıt verdi`;
		case `%s has just replied to your %s post in the thread titled "%s" in the %s group of %s.`:
			return `%s, %s %s grubundaki " %s" başlıklı konudaki %s gönderinize az önce yanıt verdi.`;
		case `When someone replies to your posts:`:
			return `Birisi gönderilerinize cevap verdiğinde:`;
		case `thread`:
			return `Konu`;
		case `Replies to the thread`:
			return `Konuya verilen yanıtlar`;
		case `%s replied to the thread "%s"`:
			return `%s, " %s" ileti dizisine yanıt verdi`;
		case `%s has just replied to a thread you have subscribed to titled "%s" in the %s group of %s.`:
			return `%s az önce %s %s grubundaki " %s" başlıklı abone olduğunuz bir konuya yanıt verdi.`;
		case `When someone posts a reply to the thread`:
			return `Birisi ileti dizisine yanıt gönderdiğinde`;
		case `No such post`:
			return `Böyle bir gönderi yok`;
		case `content`:
			return `içerik`;
		case `New threads`:
			return `Yeni konular`;
		case `New posts`:
			return `Yeni iletiler`;
		case `in`:
			return `içinde`;
		case `and`:
			return `ve`;
		case `more`:
			return `Daha`;
		case `from`:
			return `itibaren`;
		case `from email`:
			return `e-postadan`;
		case `titled`:
			return `başlıklı`;
		case `containing`:
			return `kapsamak`;
		case `%s %s the thread "%s" in %s`:
			return `%s %s, %s içindeki " %s" iş parçacığı`;
		case `replied to`:
			return `cevap verdi`;
		case `created`:
			return `yaratıldı`;
		case `%s matching %s`:
			return `%s ile eşleşen %s`;
		case "%s has just %s a thread titled \"%s\" in the %s group of %s.\n\n%s matches a content alert subscription you have created (%s).":
			return "%s, %s'nin %s grubunda \"%s\" başlıklı bir konuya sahip.\n\n%s, oluşturduğunuz bir içerik uyarısı aboneliğiyle eşleşiyor (%s).";
		case `This post`:
			return `Bu gönderi`;
		case `This thread`:
			return `Bu konu`;
		case `When someone`:
			return `Birisi`;
		case `posts or replies to a thread`:
			return `bir ileti dizisine gönderilen mesajlar veya yanıtlar`;
		case `posts a new thread`:
			return `yeni bir konu gönder`;
		case `only in the groups:`:
			return `sadece gruplarda:`;
		case `and when the`:
			return `ve ne zaman`;
		case `contains the string`:
			return `dizeyi içerir`;
		case `matches the regular expression`:
			return `normal ifadeyle eşleşir`;
		case `case sensitive`:
			return `harfe duyarlı`;
		case `author name`:
			return `yazar adı`;
		case `author email`:
			return `yazar e-postası`;
		case `subject`:
			return `konu`;
		case `message`:
			return `İleti`;
		case `No %s search term specified`:
			return `%s arama terimi belirtilmedi`;
		case "Invalid %s regex `%s`: %s":
			return "Geçersiz %s normal ifadesi `%s`: %s";
		case `No groups selected`:
			return `Grup seçilmedi`;
		case `Unknown subscription trigger type:`:
			return `Bilinmeyen abonelik tetikleyici türü:`;
		case `Send a private message to`:
			return `Adlı kişiye özel mesaj gönder`;
		case `on the`:
			return `üzerinde`;
		case `IRC network`:
			return `IRC ağı`;
		case `No nickname indicated`:
			return `Takma ad belirtilmedi`;
		case `Invalid character in nickname.`:
			return `Takma adda geçersiz karakter.`;
		case `Send an email to`:
			return `Adresine bir e-posta gönderin`;
		case `Error:`:
			return `Hata:`;
		case `Howdy %1$s,`:
			return `Merhaba% 1 $ s,`;
		case `This %3$s is located at:`:
			return `Bu% 3 $ s şu adreste bulunur:`;
		case `Here is the message that has just been posted:`:
			return `İşte yeni gönderilmiş mesaj:`;
		case `To reply to this message, please visit this page:`:
			return `Bu mesajı yanıtlamak için lütfen bu sayfayı ziyaret edin:`;
		case `There may also be other messages matching your subscription, but you will not receive any more notifications for this subscription until you've read all messages matching this subscription:`:
			return `Aboneliğinizle eşleşen başka mesajlar da olabilir, ancak bu abonelikle eşleşen tüm mesajları okuyana kadar bu abonelik için başka bildirim almayacaksınız:`;
		case `All the best,`:
			return `Herşey gönlünce olsun,`;
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
		case `No such post:`:
			return `Böyle bir gönderi yok:`;
		case `Post #%d of thread %s not found`:
			return `# %s ileti dizisi %s bulunamadı`;
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
			return `Bu gönderiye standart bağlantı. Daha fazla bilgi için Yardım sayfasındaki "Kanonik bağlantılar" bölümüne bakın.`;
		case `Reply`:
			return `Cevapla`;
		case `Reply to this post`:
			return `Bu gönderiyi yanıtla`;
		case `Subscribe`:
			return `Abone ol`;
		case `Subscribe to this thread`:
			return `Bu konuya abone ol`;
		case `Flag`:
			return `Bayrak`;
		case `Flag this post for moderator intervention`:
			return `Bu gönderiyi moderatör müdahalesi için işaretleyin`;
		case `Source`:
			return `Kaynak`;
		case `View this message's source code`:
			return `Bu mesajın kaynak kodunu görüntüleyin`;
		case `Moderate`:
			return `Orta`;
		case `Perform moderation actions on this post`:
			return `Bu gönderi üzerinde denetim işlemleri gerçekleştirin`;
		case `%s's Gravatar profile`:
			return `%s kullanıcısının Gravatar profili`;
		case `Posted by %s`:
			return `%s tarafından yayınlandı`;
		case `in reply to`:
			return `cevap olarak`;
		case `part`:
			return `Bölüm`;
		case `Posted in reply to`:
			return `Yanıt olarak yayınlandı`;
		case `Attachments:`:
			return `Ekler:`;
		case `View in thread`:
			return `Mesaj dizisinde görüntüle`;
		case `Replies to %s's post from %s`:
			return `%s tarafından gönderilen %s gönderisine yanıtlar`;
		case `Permanent link to this post`:
			return `Bu gönderiye kalıcı bağlantı`;
		case `%s's Gravatar profile"`:
			return `%s Gravatar profili "`;
		case `You seem to be posting using an unusual user-agent`:
			return `Olağandışı bir kullanıcı aracısı kullanarak gönderi paylaşıyorsunuz`;
		case `Your subject contains a suspicious keyword or character sequence`:
			return `Konunuz şüpheli bir anahtar kelime veya karakter dizisi içeriyor`;
		case `Your post contains a suspicious keyword or character sequence`:
			return `Gönderiniz şüpheli bir anahtar kelime veya karakter dizisi içeriyor`;
		case `Your top-level post is suspiciously short`:
			return `Üst düzey gönderiniz şüpheli derecede kısa`;
		case `Your post looks like spam (%d%% spamicity)`:
			return `Gönderiniz spam gibi görünüyor ( %d % %spamicity)`;
		case `from the future`:
			return `gelecekten`;
		case `just now`:
			return `Şu anda`;
		case `%d %s ago`:
			return `%d %s önce`;
		case `basic`:
			return `temel`;
		case `threaded`:
			return `dişli`;
		case `horizontal-split`:
			return `yatay bölünmüş`;
		case `vertical-split`:
			return `dikey bölünmüş`;
		case `Unknown view mode`:
			return `Bilinmeyen görünüm modu`;
		case `You have an %sunsent draft message from %s%s.`:
			return `%s %s tarafından gönderilen bir %sunsent taslak mesajınız var.`;
		case `This message is awaiting moderation.`:
			return `Bu mesaj denetlenmeyi bekliyor.`;
		case `This message has already been posted.`:
			return `Bu mesaj zaten gönderilmiştir.`;
		case `Can't post to archive`:
			return `Arşive gönderilemiyor`;
		case `Note: you are posting to a mailing list.`:
			return `Not: Bir posta listesine gönderiyorsunuz.`;
		case `Your message will not go through unless you %ssubscribe to the mailing list%s first.`:
			return `Önce %s posta listesine %s abone olmadığınız sürece mesajınız gönderilmeyecektir.`;
		case `You must then use the same email address when posting here as the one you used to subscribe to the list.`:
			return `Listeye abone olmak için kullandığınız e-posta adresini burada yayınlarken aynı e-posta adresini kullanmanız gerekir.`;
		case `If you do not want to receive mailing list mail, you can disable mail delivery at the above link.`:
			return `Posta listesi postası almak istemiyorsanız, yukarıdaki bağlantıdan posta teslimini devre dışı bırakabilirsiniz.`;
		case `Warning: the post you are replying to is from`:
			return `Uyarı: yanıtladığınız gönderinin kaynağı`;
		case `Posting to`:
			return `Şurada yayınlanıyor`;
		case `unknown post`:
			return `bilinmeyen gönderi`;
		case `Your name:`:
			return `Adınız:`;
		case `Your email address`:
			return `e`;
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
			return `Bu mesaj zaten gönderilmiştir.`;
		case `Automatic fix applied.`:
			return `Otomatik düzeltme uygulandı.`;
		case `Undo`:
			return `Geri alma`;
		case `Sorry, a problem occurred while attempting to fix your post`:
			return `Üzgünüz, gönderinizi düzeltmeye çalışırken bir sorun oluştu`;
		case `Undo information not found.`:
			return `Geri alma bilgisi bulunamadı.`;
		case `Automatic fix undone.`:
			return `Otomatik düzeltme geri alındı.`;
		case `Warning:`:
			return `Uyarı:`;
		case `Ignore`:
			return `Göz ardı etmek`;
		case `Explain`:
			return `Açıklamak`;
		case `Fix it for me`:
			return `Benim için düzelt`;
		case `You've attempted to post %d times in the past %s. Please wait a little bit before trying again.`:
			return `Geçmiş %s içinde %d kez göndermeye çalıştınız. Tekrar denemeden önce lütfen biraz bekleyin.`;
		case `You've attempted to post %d times in the past %s. Please solve a CAPTCHA to continue.`:
			return `Geçmiş %s içinde %d kez göndermeye çalıştınız. Devam etmek için lütfen bir CAPTCHA çözün.`;
		case `Your message has been saved, and will be posted after being approved by a moderator.`:
			return `Mesajınız kaydedildi ve bir moderatör tarafından onaylandıktan sonra gönderilecektir.`;
		case `Unknown action`:
			return `Bilinmeyen eylem`;
		case `Posting status`:
			return `Gönderi durumu`;
		case `Validating...`:
			return `Doğrulanıyor ...`;
		case `Verifying reCAPTCHA...`:
			return `ReCAPTCHA doğrulanıyor ...`;
		case `Connecting to server...`:
			return `Sunucuya baglanıyor...`;
		case `Sending message to server...`:
			return `Sunucuya mesaj gönderiliyor ...`;
		case `Message sent.`:
			return `Mesajı gönderildi.`;
		case `Waiting for message announcement...`:
			return `Mesaj duyurusu bekleniyor ...`;
		case `Message posted! Redirecting...`:
			return `Mesaj gönderildi! Yönlendiriliyor ...`;
		case `%s. Please solve a CAPTCHA to continue.`:
			return `%s. Devam etmek için lütfen bir CAPTCHA çözün.`;
		case `Spam check error:`:
			return `Spam kontrolü hatası:`;
		case `Try clearing your browser's cookies. Create an account to avoid repeated incidents.`:
			return `Tarayıcınızın çerezlerini temizlemeyi deneyin. Tekrarlanan olaylardan kaçınmak için bir hesap oluşturun.`;
		case `Malformed Base64 in read post history cookie.`:
			return `Okuma geçmişi tanımlama bilgisinde hatalı biçimlendirilmiş Base64.`;
		case `Malformed deflated data in read post history cookie`:
			return `Kayıt geçmişi tanımlama çerezinde hatalı biçimlendirilmiş sönük veriler`;
		case `Please enter a username`:
			return `Lütfen bir kullanıcı adı giriniz`;
		case `Username too long`:
			return `Kullanıcı adı çok uzun`;
		case `Password too long`:
			return `Parola çok uzun`;
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
			return `StopForumSpam, spam yapan biri olabileceğinizi düşünüyor (en son %s görülme: %s, sıklık: %s)`;
		case `Log in`:
			return `Oturum aç`;
		case `Username:`:
			return `Kullanıcı adı:`;
		case `Password:`:
			return `Parola:`;
		case `Remember me`:
			return `Beni Hatırla`;
		case `Register`:
			return `Kayıt ol`;
		case `to keep your preferences<br>and read post history on the server.`:
			return `tercihlerinizi korumak <br> ve sunucuda gönderi geçmişini okumak için.`;
		case `Confirm:`:
			return `Onaylamak:`;
		case `Please pick your password carefully.`:
			return `Lütfen şifrenizi dikkatlice seçin.`;
		case `There are no password recovery options.`:
			return `Şifre kurtarma seçeneği yoktur.`;
		case `Passwords do not match`:
			return `Parolalar uyuşmuyor`;
		case `First`:
			return `İlk`;
		case `Prev`:
			return `Önceki`;
		case `Next`:
			return `Sonraki`;
		case `Last`:
			return `Son`;
		case `Advanced Search`:
			return `gelişmiş Arama`;
		case `Find posts with...`:
			return `Şu gönderileri bul ...`;
		case `all these words:`:
			return `tüm bu kelimeler:`;
		case `this exact phrase:`:
			return `tam olarak şu ifade:`;
		case `none of these words:`:
			return `bu kelimelerin hiçbiri:`;
		case `posted in the group:`:
			return `grupta yayınlandı:`;
		case `posted by:`:
			return `tarafından gönderildi:`;
		case `posted by (email):`:
			return `gönderen (e-posta):`;
		case `in threads titled:`:
			return `başlıklı konu başlığında:`;
		case `containing:`:
			return `kapsamak:`;
		case `posted between:`:
			return `arasında yayınlandı:`;
		case `yyyy-mm-dd`:
			return `yyyy-aa-gg`;
		case `posted as new thread:`:
			return `yeni konu olarak yayınlandı:`;
		case `Advanced search`:
			return `Gelişmiş Arama`;
		case `Search`:
			return `Arama`;
		case `Invalid date: %s (%s)`:
			return `Geçersiz tarih: %s (%s)`;
		case `Start date must be before end date`:
			return `Başlangıç ​​tarihi, bitiş tarihinden önce olmalıdır`;
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
			return `Eski yönlendirme - makale bulunamadı`;
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
			return `Üzerinde yeni yayınlar`;
		case `New threads on`:
			return `Yeni konular`;
		case `No thread specified`:
			return `Konu belirtilmedi`;
		case `Viewing thread in basic view mode – click a post's title to open it in %s view mode`:
			return `Mesaj dizisi temel görünüm modunda görüntüleniyor - %s görüntüleme modunda açmak için bir gönderinin başlığını tıklayın`;
		case `No post specified`:
			return `Gönderi belirtilmedi`;
		case `(view single post)`:
			return `(tek gönderiyi görüntüle)`;
		case `Invalid URL`:
			return `Geçersiz URL`;
		case `No such group`:
			return `Böyle bir grup yok`;
		case `Posting to %s`:
			return `%s adresinde yayınlanıyor`;
		case `New thread`:
			return `Yeni Konu`;
		case `Replying to "%s"`:
			return `" %s" yanıtlanıyor`;
		case `Post reply`:
			return `Cevap Gönder`;
		case `Posting`:
			return `Gönderi`;
		case `No post ID specified`:
			return `Gönderi kimliği belirtilmedi`;
		case `Composing message`:
			return `Mesaj oluşturma`;
		case `Please log in to do that`:
			return `Lütfen bunu yapmak için giriş yapın`;
		case `Subscribe to thread`:
			return `Konuya abone ol`;
		case `No subscription specified`:
			return `Abonelik belirtilmedi`;
		case `View subscription`:
			return `Aboneliği görüntüle`;
		case `Unsubscribe`:
			return `Aboneliği iptal et`;
		case `You are not a moderator`:
			return `Sen bir moderatör değilsin`;
		case `Moderating post "%s"`:
			return `" %s" yayını denetleniyor`;
		case `Moderate post`:
			return `Orta düzey yayın`;
		case `You can't flag posts`:
			return `Gönderileri işaretleyemezsiniz`;
		case `Flag "%s" by %s`:
			return `%s tarafından " %s" işaretleyin`;
		case `Flag post`:
			return `Gönderiyi işaretle`;
		case `You can't approve moderated drafts`:
			return `Denetlenen taslakları onaylayamazsınız`;
		case `Approving moderated draft`:
			return `Denetlenen taslak onaylanıyor`;
		case `Registration`:
			return `Kayıt`;
		case `Login error`:
			return `Sisteme giriş hatası`;
		case `Registration error`:
			return `Kayıt Hatası`;
		case `Account`:
			return `Hesap`;
		case `Change Password`:
			return `Şifre değiştir`;
		case `Export Data`:
			return `Verileri Dışa Aktar`;
		case `Delete Account`:
			return `Hesabı sil`;
		case `Help`:
			return `Yardım`;
		case `Forum activity summary`:
			return `Forum etkinliği özeti`;
		case `Feed type not specified`:
			return `Feed türü belirtilmedi`;
		case `Unknown feed type`:
			return `Bilinmeyen besleme türü`;
		case `hours parameter exceeds limit`:
			return `saat parametresi sınırı aşıyor`;
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
			return `Uyarı: tanımlama bilgisi boyutu RFC 2109 sınırına yaklaşıyor.`;
		case `Please consider %screating an account%s to avoid losing your read post history.`:
			return `Okuma gönderi geçmişinizi kaybetmemek için lütfen %s hesabınızı %s göstermeyi düşünün.`;
		case `Forums`:
			return `Forumlar`;
		case `%s group`:
			return `%s grubu`;
		case `View subscription:`:
			return `Aboneliği görüntüle:`;
		case `It looks like there's nothing here! No posts matched this subscription so far.`:
			return `Görünüşe göre burada hiçbir şey yok! Şu ana kadar bu abonelikle eşleşen gönderi yok.`;
		case `This subscription has been deactivated.`:
			return `Bu abonelik devre dışı bırakıldı.`;
		case `If you did not intend to do this, you can reactivate the subscription's actions on your %ssettings page%s.`:
			return `Bunu yapmak istemediyseniz, aboneliğin eylemlerini %ssettings sayfanızda %s yeniden etkinleştirebilirsiniz.`;
		case `Hint`:
			return `İpucu`;
		case "Is the CAPTCHA too hard?\nRefresh the page to get a different question,\nor ask in the %s#d IRC channel on Freenode%s.":
			return `CAPTCHA çok mu zor?\nFarklı bir soru almak için sayfayı yenileyin\nveya %sFreenode üzerindeki #d IRC kanalında%s sorun.`;
		case `Unknown or expired CAPTCHA challenge`:
			return `Bilinmeyen veya süresi dolmuş CAPTCHA testi`;
		case `The answer is incorrect`:
			return `Cevap yanlış`;
		case `Akismet thinks your post looks like spam`:
			return `Akismet, gönderinizin spam gibi göründüğünü düşünüyor`;
		case `Akismet error:`:
			return `Akismet hatası:`;
		case `Latest announcements`:
			return `Son duyurular`;
		case `Active discussions`:
			return `Aktif tartışmalar`;
		case `ProjectHoneyPot thinks you may be a spammer (%s last seen: %d days ago, threat score: %d/255, type: %s)`:
			return `ProjectHoneyPot, spam yapan olabileceğinizi düşünüyor (en son %s görülme: %d gün önce, tehdit puanı: %d / 255, tür: %s)`;
		case `From`:
			return `Nereden`;
		case `Date`:
			return `Tarih`;
		case `In reply to`:
			return `Yanıt olarak`;
		case `Attachments`:
			return `Ekler`;
		case `Parent post is not quoted.`:
			return `Ana gönderi alıntı yapılmamış.`;
		case `When replying to someone's post, you should provide some context for your replies by quoting the revelant parts of their post.`:
			return `Birinin gönderisine yanıt verirken, gönderisinin açıklayıcı kısımlarını alıntılayarak yanıtlarınız için bir bağlam sağlamalısınız.`;
		case `Depending on the software (or its configuration) used to read your message, it may not be obvious which post you're replying to.`:
			return `Mesajınızı okumak için kullanılan yazılıma (veya yapılandırmasına) bağlı olarak, hangi gönderiyi yanıtladığınız belli olmayabilir.`;
		case `Thus, when writing a reply, don't delete all quoted text: instead, leave just enough to provide context for your reply.`:
			return `Bu nedenle, bir yanıt yazarken, alıntılanan tüm metni silmeyin: bunun yerine, yanıtınız için bağlam sağlamak için yeterli bırakın.`;
		case `You can also insert your replies inline (interleaved with quoted text) to address specific parts of the parent post.`:
			return `Üst gönderinin belirli bölümlerine hitap etmek için yanıtlarınızı satır içi (alıntılanmış metinle karıştırılmış) olarak da ekleyebilirsiniz.`;
		case `You are quoting a post other than the parent.`:
			return `Ebeveyn dışında bir gönderiden alıntı yapıyorsunuz.`;
		case `When replying a message, the message you are replying to is referenced in the post's headers.`:
			return `Bir mesajı yanıtlarken, yanıtladığınız mesaj, yazının başlıklarında belirtilir.`;
		case `Depending on the software (or its configuration) used to read your message, your message may be displayed below its parent post.`:
			return `Mesajınızı okumak için kullanılan yazılıma (veya yapılandırmasına) bağlı olarak, mesajınız ana gönderisinin altında görüntülenebilir.`;
		case `If your message contains a reply to a different post, following the conversation may become somewhat confusing.`:
			return `Mesajınız farklı bir gönderiye cevap içeriyorsa, konuşmayı takip etmek biraz kafa karıştırıcı olabilir.`;
		case `Thus, make sure to click the "Reply" link on the actual post you're replying to, and quote the parent post for context.`:
			return `Bu nedenle, yanıtladığınız asıl gönderideki "Yanıtla" bağlantısını tıkladığınızdan ve bağlam için ana gönderiden alıntı yaptığınızdan emin olun.`;
		case `Parent post is not indicated.`:
			return `Ana gönderi belirtilmemiştir.`;
		case `When quoting someone's post, you should leave the "On (date), (author) wrote:" line.`:
			return `Birinin gönderisinden alıntı yaparken, "Tarih (tarih), (yazar) şunu yazdı:" satırını bırakmalısınız.`;
		case `Thus, this line provides important context for your replies regarding the structure of the conversation.`:
			return `Bu nedenle, bu satır, sohbetin yapısıyla ilgili yanıtlarınız için önemli bir bağlam sağlar.`;
		case `You are quoting multiple posts.`:
			return `Birden fazla gönderiden alıntı yapıyorsunuz.`;
		case `Thus, you should avoid replying to multiple posts in one reply.`:
			return `Bu nedenle, tek bir yanıtta birden fazla gönderiye yanıt vermekten kaçınmalısınız.`;
		case `If applicable, you should split your message into several, each as a reply to its corresponding parent post.`:
			return `Mümkünse, mesajınızı, her biri ilgili ana gönderiye yanıt olarak birkaç bölüme ayırmalısınız.`;
		case `You are top-posting.`:
			return `En çok göndericisin.`;
		case `When replying a message, it is generally preferred to add your reply under the quoted parent text.`:
			return `Bir mesajı yanıtlarken, genellikle yanıtınızı alıntılanmış ana metnin altına eklemeniz tercih edilir.`;
		case `Depending on the software (or its configuration) used to read your message, your message may not be displayed below its parent post.`:
			return `Mesajınızı okumak için kullanılan yazılıma (veya yapılandırmasına) bağlı olarak, mesajınız ana gönderisinin altında görüntülenmeyebilir.`;
		case `In such cases, the quoted text provides context for your reply, and readers would need to first read the quoted text below your reply for context.`:
			return `Bu gibi durumlarda, alıntılanan metin cevabınız için bağlam sağlar ve okuyucuların bağlam için ilk önce cevabınızın altındaki alıntılanan metni okumaları gerekir.`;
		case `Thus, you should add your reply below the quoted text (or reply to individual paragraphs inline), rather than above it.`:
			return `Bu nedenle, cevabınızı alıntı yapılan metnin üstüne eklemelisiniz (veya tek tek paragrafları satır içi olarak yanıtlamalısınız).`;
		case `The ratio between quoted and added text is vastly disproportional.`:
			return `Alıntılanan ve eklenen metin arasındaki oran büyük ölçüde orantısızdır.`;
		case `Quoting should be limited to the amount necessary to provide context for your replies.`:
			return `Alıntı yapma, yanıtlarınıza bağlam sağlamak için gereken miktarla sınırlı olmalıdır.`;
		case `Quoting posts in their entirety is thus rarely necessary, and is a waste of vertical space.`:
			return `Bu nedenle, yazıların tamamını alıntılamak nadiren gereklidir ve dikey alan israfıdır.`;
		case `Please trim the quoted text to just the relevant parts you're addressing in your reply, or add more content to your post.`:
			return `Lütfen alıntılanan metni yanıtınızda ele aldığınız ilgili kısımlarla birlikte kısaltın veya yayınınıza daha fazla içerik ekleyin.`;
		case `Don't use URL shorteners.`:
			return `URL kısaltıcılar kullanmayın.`;
		case `URL shortening services, such as TinyURL, are useful in cases where space is at a premium, e.g. in IRC or Twitter messages.`:
			return `TinyURL gibi URL kısaltma hizmetleri, alanın önemli olduğu durumlarda kullanışlıdır, ör. IRC veya Twitter mesajlarında.`;
		case `In other circumstances, however, they provide little benefit, and have the significant disadvantage of being opaque:`:
			return `Ancak diğer durumlarda, çok az fayda sağlarlar ve opak olma gibi önemli dezavantajlara sahiptirler:`;
		case `readers can only guess where the link will lead to before they click it.`:
			return `okuyucular, yalnızca bağlantıyı tıklamadan önce bağlantının nereye gideceğini tahmin edebilir.`;
		case `Additionally, URL shortening services come and go - your link may work today, but might not in a year or two.`:
			return `Ek olarak, URL kısaltma hizmetleri gelir ve gider - bağlantınız bugün çalışabilir, ancak bir veya iki yıl içinde olmayabilir.`;
		case `Thus, do not use URL shorteners when posting messages online - post the full link instead, even if it seems exceedingly long.`:
			return `Bu nedenle, çevrimiçi mesaj gönderirken URL kısaltıcıları kullanmayın - bunun yerine, aşırı uzun görünse bile tam bağlantıyı gönderin.`;
		case `If it is too long to be inserted inline, add it as a footnote instead.`:
			return `Satır içi eklenemeyecek kadar uzunsa, bunun yerine dipnot olarak ekleyin.`;
		case `Could not expand URL:`:
			return `URL genişletilemedi:`;
		case `Don't put links in the subject.`:
			return `Konuya bağlantı koymayın.`;
		case `Links in message subjects are usually not clickable.`:
			return `Mesaj konularındaki bağlantılar genellikle tıklanabilir değildir.`;
		case `Please move the link in the message body instead.`:
			return `Lütfen bağlantıyı mesaj gövdesine taşıyın.`;
		case `Avoid replying to very old threads.`:
			return `Çok eski konuları yanıtlamaktan kaçının.`;
		case `The thread / post you are replying to is very old.`:
			return `Yanıtladığınız konu / gönderi çok eski.`;
		case `Consider creating a new thread instead of replying to an existing one.`:
			return `Mevcut bir ileti dizisini yanıtlamak yerine yeni bir ileti dizisi oluşturmayı düşünün.`;
		case `BlogSpam.net thinks your post looks like spam:`:
			return `BlogSpam.net, gönderinizin spam gibi göründüğünü düşünüyor:`;
		case `BlogSpam.net error:`:
			return `BlogSpam.net hatası:`;
		case `BlogSpam.net unexpected response:`:
			return `BlogSpam.net beklenmeyen yanıt:`;
		case `Perform which moderation actions on this post?`:
			return `Bu gönderide hangi denetim işlemlerini gerçekleştirin?`;
		case `Delete local cached copy of this post from DFeed's database`:
			return `Bu gönderinin yerel önbelleğe alınmış kopyasını DFeed'in veritabanından silin`;
		case `Ban poster (place future posts in moderation queue)`:
			return `Posteri yasakla (gelecekteki gönderileri denetim kuyruğuna yerleştirin)`;
		case `Delete source copy from %-(%s/%)`:
			return `%-(%s/%) kaynağından kaynak kopyayı sil`;
		case `Reason:`:
			return `Nedeni:`;
		case `It looks like you've already flagged this post.`:
			return `Görünüşe göre bu gönderiyi zaten işaretlemişsiniz.`;
		case `Would you like to %sunflag it%s?`:
			return `%s ile %s işaretlemek ister misiniz?`;
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
			return `%s bayrağı %s ister misiniz?`;
		case `Are you sure you want to unflag this post?`:
			return `Bu gönderinin işaretini kaldırmak istediğinizden emin misiniz?`;
		case `Unflag`:
			return `İşareti kaldır`;
		case `You've already unflagged this post.`:
			return `Bu gönderinin işaretini zaten kaldırdınız.`;
		case `Post unflagged.`:
			return `İşaretsiz yayınlayın.`;
		case `You can view it here.`:
			return `Buradan görüntüleyebilirsiniz.`;
		case `This is not a post in need of moderation. Its status is currently:`:
			return `Bu, denetlenmesi gereken bir gönderi değil. Şu anda durumu:`;
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
	// TODO!
	switch (unit)
	{
		case "second":
		case "minute":
		case "hour":
		case "day":
		case "week":
		case "month":
		case "year":

		case "thread":
		case "post":
		case "forum post":
		case "subscription":
		case "unread post":
		case "registered user":
		case "visit":
			return unit ~ "s";

		case "new reply":
			return "new replies";

		case "user has created":
			return "users have created";

		default:
			assert(false, "Unknown unit: " ~ unit);
	}
}

string plural(string unit)(long amount)
{
	// TODO!
	static immutable unitPlural = pluralOf(unit);
	return amount == 1 ? unit : unitPlural;
}

const WeekdayShortNames = ["Paz", "Pzt", "Sal", "Çar", "Per", "Cum", "Cmt"];
const WeekdayLongNames = ["Pazar", "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi"];
const MonthShortNames = ["Oca", "Şub", "Mar", "Nis", "May", "Haz", "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara"];
const MonthLongNames = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran", "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"];
