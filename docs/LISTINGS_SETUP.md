# AlgoRoom ilan altyapısını kurma

Bu sürüm gerçek ilanları Firestore'dan okur. Fotoğraflar Cloud Storage'da, ilanla ilgili özel konuşmalar ve favoriler Firestore'da tutulur. Firebase kullanmadan açılan eski demo ayrı kalır.

## Firebase Console

1. **Project Overview** bölümünden mevcut AlgoRoom projesini aç. **Authentication** altında kullandığın giriş sağlayıcılarının ve Pages alan adının etkin olduğunu kontrol et.
2. **Build → Firestore Database → Create database** yolundan varsayılan Firestore veritabanını oluştur veya mevcut veritabanını kullan. Üretim modunu seç.
3. **Build → Storage → Get started** yolundan mevcut projeye ait bucket'ı etkinleştir. Console'da görünen bucket adını kopyala. Cloud Storage erişimi Firebase faturalandırma koşullarına tabidir. [Cloud Storage plan gereksinimleri](https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024)
4. Firestore ve Storage üzerinde önceden yazılmış kurallar varsa bu depodaki kuralları mevcut kurallarla birleştir. Özellikle var olan özel koleksiyonları ve ilgili indeksleri koru. Storage kurallarının Firestore ilan durumunu okuyabilmesi için Firebase Console ilgili servis yetkisini sorarsa mevcut proje için inceleyip etkinleştir. [Koleksiyon güvenlik kuralları](https://firebase.google.com/docs/firestore/security/rules-conditions) · [Storage ve Firestore erişim kuralları](https://firebase.google.com/docs/storage/security/rules-conditions)

## Kuralları ve indeksleri yükle

Firebase CLI'da doğru proje ile oturum aç. Aşağıdaki komutu, gözden geçirilmiş kurallar ve indeksler bulunan proje kökünde çalıştır. İndeksler Console'da hazır olduktan sonra filtreli sorguları dene.

```powershell
firebase deploy --only firestore:rules,firestore:indexes,storage --project algeroom
```

Mevcut bir `listings` koleksiyonu varsa belgeleri yeni şemayla karşılaştır. Bu sürümün sorguları durum, sıralama tarihi ve normalize konum anahtarları kullanır. Eski belgelerin biçimini değiştirmeden önce yedek al.

## Web fotoğrafları ve GitHub Pages

- Firebase web yapılandırmasındaki `storageBucket` değerini GitHub deposuna **Settings → Secrets and variables → Actions → Variables → New repository variable** bölümünden `FIREBASE_STORAGE_BUCKET` adıyla ekle.
- Mevcut beş Firebase değişkenini koru. İlan bucket değişkenini de okuyan [deploy-web-listings.yml](deploy-web-listings.yml) dosyasının içeriğini GitHub'daki mevcut `.github/workflows/deploy-web.yml` dosyasına uygula.
- CORS için `storage.cors.json` dosyasındaki alan adını gerçek Pages adresinle eşleştir. Proje kökünde Google Cloud CLI ile aşağıdaki komutu, kendi bucket adınla çalıştır. Bucket'ta önceden CORS ayarı varsa gerekli kaynakları birleştir. [Firebase web indirme ve CORS kurulumu](https://firebase.google.com/docs/storage/web/download-files)

```powershell
gcloud storage buckets update gs://BUCKET_ADI --cors-file=storage.cors.json
```

- Android veya iOS'ta yerel derleme için `firebase-auth.local.json` dosyasına aynı adlı string alanı ekle ve uygulamayı `flutter run --dart-define-from-file=firebase-auth.local.json` ile yeniden başlat.

## Akışın sınırları

- Beraber ev arayan kullanıcı için kira alanı bütçe anlamına gelir. Mevcut ev alanları saklanmaz. Kullanıcının seçtiği taşınma günü UTC takvim tarihi olarak kaydedilir. Oluşturma ve güncelleme zamanını Firestore belirler.
- Şehir, ilçe, kira sınırları ve sıralama Firestore sorgusundadır. İlan türü, ev tipi, eşya durumu ve taşınma aralığı, bu sorgunun döndürdüğü aktif ilanlar üzerinde uygulanır. İlk sürümde ilan akışı sayfalanmaz.
- Sayaç, ilan sahibi hariç Firebase hesabı başına bir görüntüleme kaydeder. Şikâyet belgeleri yönetici yetkisiyle okunur. Moderasyon arayüzü bu sürümün kapsamı dışındadır.
- Fotoğraflar için herkese açık bağlantı Firestore'a yazılmaz. Silme işlemi ilanı gizledikten sonra fotoğrafları kaldırır. Bir ağ hatasıyla yarıda kalırsa İlanlarım ekranından silme yeniden denenebilir. Tamamlanmamış taslaklar aynı ekrandan yönetilebilir. Firestore alt koleksiyonları ana belgeyle otomatik silinmediği için görüntüleme ve şikâyet kayıtları için ayrıca yönetici saklama politikası gerekir.
- Kullanıcı kartında Firebase profilinin görünen adı kullanılır. Telefon ve e-posta ilan belgesine yazılmaz. Kaynakta genel mesajlaşma bulunmadığı için uygulamada ilan bazlı özel gelen kutusu vardır.

## Doğrulama

```powershell
flutter pub get
dart format lib test
flutter analyze
flutter test
npm --prefix test/firebase_rules install
firebase emulators:exec --project demo-algoroom --only firestore,storage "npm --prefix test/firebase_rules test"
```

İki test hesabıyla ilan yayınla, fotoğrafları ve kapağı doğrula, ilanı ikinci hesaptan açıp favorile ve mesaj gönder. İlk hesapla gelen kutusunu aç. İlk hesapla ilanı pasife al ve ikinci hesapta görünmediğini kontrol et. Tekrar yayınla, düzenle ve son olarak fotoğrafların temizlendiğini Storage Console'da doğrula.
