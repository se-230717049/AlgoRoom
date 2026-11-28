# Mimari

Özellikler lib/features altında toplanır. Domain modeli ve repository sözleşmesi Dart kullanır. Repository implementasyonlarını Riverpod sağlar. GoRouter açılış ve uygulama rotalarını yönetir. Tema ve ortak durum görünümleri core altında, TR/EN kaynakları lib/l10n altındadır.

Yerel demo repository kurgusal veriler kullanır. SharedPreferences yalnızca cihazdaki onboarding, tema ve dil tercihlerine ayrılır. Demo favorileri oturum süresince bellekte tutulur. Üretim repository ayrı giriş yapılandırmasına sahip olacaktır.

Firebase aşamasında doğrulanmış UID ve App Check sunucuda kontrol edilir. Eşleşme, engelleme, mesaj ve moderasyon işlemleri sunucuya taşınır. İstemci Firestore akışları ve sayfalı sorgular üzerinden erişim sağlar.

## İlanlar

lib/features/listings altında Firebase bağımsız ilan modeli, Firebase repository, form ve keşif ekranları bulunur. Riverpod akışları Firestore sorgularını besler. GoRouter ilan yönetimi ve mesaj sayfalarını oturum gerektiren hesap rotasının altında açar. Mevcut yerel demo ayrı rotada kalır.

Yayınlamadan önce Firestore'da özel taslak açılır. İlan dosyaları kullanıcı ve ilan kimliği altında yüklenir. Firestore işlemi taslağı yayınlar ve değişiklik sürümünü doğrular. Silme önce ilanı görünmez yapar ve aynı dizindeki Storage nesnelerini temizler. Görüntülenme artışı ve izleyici kaydı atomik yazılır.