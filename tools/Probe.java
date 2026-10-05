import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;

/** Usage: java Probe.java <url>...  Uses the JDK trust store, so it fails if mycas is not trusted. */
public class Probe {
  public static void main(String[] args) {
    HttpClient client = HttpClient.newBuilder()
        .connectTimeout(Duration.ofSeconds(10))
        .followRedirects(HttpClient.Redirect.NEVER)
        .build();
    for (String url : args) {
      long start = System.nanoTime();
      String result;
      try {
        HttpResponse<String> resp = client.send(
            HttpRequest.newBuilder(URI.create(url)).timeout(Duration.ofSeconds(30)).GET().build(),
            HttpResponse.BodyHandlers.ofString());
        String body = resp.body().replaceAll("\\s+", " ");
        result = resp.statusCode() + "  " + body.substring(0, Math.min(90, body.length()));
      } catch (Exception e) {
        result = "ERROR " + e.getClass().getSimpleName() + ": " + e.getMessage();
      }
      System.out.printf("%-48s %s  (%d ms)%n", url, result, (System.nanoTime() - start) / 1_000_000);
    }
  }
}
