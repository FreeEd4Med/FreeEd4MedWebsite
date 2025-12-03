<?php
header("Content-Type: application/json; charset=UTF-8");
require_once __DIR__ . '/libs/simplepie/autoloader.php';

$feeds = [
  "https://feeds.bbci.co.uk/news/health/rss.xml",
  "https://www.who.int/feeds/entity/mediacentre/news/en/rss.xml",
  "https://news.un.org/feed/subscribe/en/news/topic/health/feed/rss.xml",
  "https://www.medpagetoday.com/rss.xml"
];

$headlines = [];

foreach ($feeds as $url) {
    $feed = new SimplePie();
    $feed->set_feed_url($url);
    $feed->enable_cache(false);
    $feed->init();

    if ($feed->error()) continue;

    $items = $feed->get_items(0, 6);
    foreach ($items as $item) {
        $title = htmlspecialchars($item->get_title());
        $link = htmlspecialchars($item->get_permalink());
        $headlines[] = ["title" => $title, "link" => $link];
        if (count($headlines) >= 20) break 2;
    }
}

echo json_encode($headlines);
?>
