# Deprem Atlası

İstanbul'da deprem konuşulunca hep aynı sorular geliyor: "Bizim mahallenin zemini nasıl?", "Bir şey olursa nereye gideceğiz?" Bu bilgilerin çoğu İBB'nin ve diğer kurumların yayınladığı verilerde aslında var ama dağınık duruyor. Ben de bir harita teknikeri olarak hepsini tek bir haritada toplamak istedim.

Deprem Atlası, İstanbul'un 39 ilçesindeki 958 mahalle için bu bilgileri sade bir harita üzerinde gösteriyor. Telefona bir kere açtıktan sonra internet olmadan da çalışıyor.

👉 **Uygulama:** https://maelstoorm.github.io/deprem-atlasi/

## Neler var?

- **Zemin bilgisi (Vs30):** Mahallenizin zemini yumuşak mı, sert mi?
- **Senaryo depremi:** İBB'nin bina hasarı ve geçici barınma tahminleri
- **Tsunami:** Su baskını riski olan kıyı alanları (İBB–ODTÜ çalışması)
- **Toplanma alanları:** Size en yakın afet toplanma alanı, adres arama
- **Son depremler ve bildirimler:** Kandilli ve AFAD verileriyle
- **Acil durum ekranı:** Tek tuşla 112'yi arama, yakınlarınıza konumunuzla "İyiyim" mesajı
- **Herkes için:** Büyüklerimiz de rahatça kullanabilsin diye yazılar ve düğmeler büyük, ekran sade

## Bilmeniz gereken

Bu resmi bir rapor değil ve hiçbir kurumu temsil etmiyor. Gösterilen rakamlar mahalle geneli için yapılmış tahminler, tek tek binaların durumunu göstermiyor. Her bilginin kaynağını uygulamanın içinde yazdım.

Bir hata görürseniz ya da öneriniz varsa [Issues](https://github.com/MaelStoorm/deprem-atlasi/issues) kısmından yazabilirsiniz, çok sevinirim.

## Android uygulaması

`android/` klasöründe Google Play için hazırlanan Android uygulaması var. Uygulama siteyi telefonun içindeki kopyasından açar (internet olmadan da çalışır); kök klasördeki site dosyaları her derlemede uygulamaya otomatik kopyalanır, yani ayrıca güncellemek gerekmez.

- `main` dalına her gönderimde GitHub Actions **imzasız** bir AAB derler ve `builds` dalına koyar: `deprem-atlasi-unsigned.aab`, hangi commit'ten derlendiği `commit.txt` içinde. Derleme başarısız olursa hata kaydı `build-log.txt` olarak yazılır, son sağlam AAB yerinde kalır.
- Paket adı: `com.maelstorm.deprematlasi`. Sürüm `android/app/build.gradle.kts` içinde; Play'e her yeni yüklemede `versionCode` bir artırılmalı.
- Play'e yüklemeden önce AAB kendi yükleme anahtarınızla imzalanır, örneğin: `jarsigner -keystore yukleme.jks -signedjar deprem-atlasi.aab deprem-atlasi-unsigned.aab yukleme`. Anahtar dosyası ve şifreler depoya **konmaz**.
- Uygulama simgeleri `ikon-maskable-512.png` dosyasından `python3 android/araclar/ikon_uret.py` ile üretilir.

## Telif hakkı

© 2026 Egemen Çalıkoğlu. **Tüm hakları saklıdır.**

Depo herkese açık ama kod, tasarım ve içerik açık kaynak **değil**. Yazılı iznim olmadan kopyalanamaz, değiştirilemez, başka bir uygulamada ya da sitede kullanılamaz ve dağıtılamaz. Ayrıntılar [LICENSE](LICENSE) dosyasında.

Üçüncü taraf içerikler (yazı tipi, OpenStreetMap verisi, kurum verileri) kendi lisanslarına tabidir.

İzin ya da iş birliği için [Issues](https://github.com/MaelStoorm/deprem-atlasi/issues) üzerinden bana ulaşabilirsiniz.
