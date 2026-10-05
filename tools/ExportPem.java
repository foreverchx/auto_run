import java.io.FileInputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.Key;
import java.security.KeyStore;
import java.security.cert.Certificate;
import java.util.Base64;

/** Usage: java ExportPem.java <keystore.jks> <alias> <outDir>  (password from env MYCAS_PW) */
public class ExportPem {
  public static void main(String[] args) throws Exception {
    char[] pw = System.getenv("MYCAS_PW").toCharArray();
    KeyStore ks = KeyStore.getInstance("JKS");
    try (FileInputStream in = new FileInputStream(args[0])) {
      ks.load(in, pw);
    }
    Key key = ks.getKey(args[1], pw);
    Certificate cert = ks.getCertificate(args[1]);
    Base64.Encoder enc = Base64.getMimeEncoder(64, "\n".getBytes());
    Path out = Path.of(args[2]);
    Files.createDirectories(out);
    Files.writeString(out.resolve("mycas.key"),
        "-----BEGIN PRIVATE KEY-----\n" + enc.encodeToString(key.getEncoded()) + "\n-----END PRIVATE KEY-----\n");
    Files.writeString(out.resolve("mycas.crt"),
        "-----BEGIN CERTIFICATE-----\n" + enc.encodeToString(cert.getEncoded()) + "\n-----END CERTIFICATE-----\n");
    System.out.println("exported " + key.getFormat() + " key and certificate to " + out);
  }
}
