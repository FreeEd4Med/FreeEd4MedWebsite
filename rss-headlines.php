<?php
header("Content-Type: application/json; charset=UTF-8");
// No external libraries needed

// RSS Feeds for "AI Music" and "Music in Medicine"
$feeds = [
    // Google News: AI Music Industry
    "https://news.google.com/rss/search?q=AI+Music+Industry+OR+Generative+Audio&hl=en-US&gl=US&ceid=US:en",
    // Google News: Music Therapy / Medicine
    "https://news.google.com/rss/search?q=Music+Therapy+OR+Music+Medicine+OR+Clinical+Music&hl=en-US&gl=US&ceid=US:en",
    // ScienceDaily: Music
    "https://www.sciencedaily.com/rss/mind_brain/music.xml"
];

$headlines = [];
$max_items_per_feed = 5;

// Detect User Country (Simple IP Geolocation)
$user_country = 'US'; // Default
try {
    $ip = $_SERVER['REMOTE_ADDR'];
    // Use a free API (limited rate, but fine for client-side calls)
    // Set a short timeout to avoid blocking
    $ctx = stream_context_create(['http'=> ['timeout' => 1]]);
    $geo = @file_get_contents("http://ip-api.com/json/$ip?fields=countryCode", false, $ctx);
    if ($geo) {
        $data = json_decode($geo, true);
        if (isset($data['countryCode'])) {
            $user_country = $data['countryCode'];
        }
    }
} catch (Exception $e) {
    // Fallback to US
}

foreach ($feeds as $url) {
    try {
        // Append Geo parameters to Google News URLs
        if (strpos($url, 'news.google.com') !== false) {
            $url .= "&gl=$user_country&ceid=$user_country:en";
        }

        // Suppress warnings for invalid XML
        $rss = @simplexml_load_file($url);
        if ($rss === false) continue;

        $count = 0;
        foreach ($rss->channel->item as $item) {
            if ($count >= $max_items_per_feed) break;
            
            $title = (string)$item->title;
            $link = (string)$item->link;
            $pubDate = (string)$item->pubDate;
            $dateTs = strtotime($pubDate);
            $dateIso = $dateTs ? date('c', $dateTs) : null;

            // Filter out very old news (> 30 days)
            if ($dateTs && (time() - $dateTs) > (30 * 24 * 3600)) continue;

            $headlines[] = [
                "title" => strip_tags($title),
                "link" => $link,
                "date" => $dateIso,
                "timestamp" => $dateTs
            ];
            $count++;
        }
    } catch (Exception $e) {
        continue;
    }
}

// Sort by date (newest first)
usort($headlines, function($a, $b) {
    return $b['timestamp'] - $a['timestamp'];
});

// Return top 15
echo json_encode(array_slice($headlines, 0, 15));
?>
