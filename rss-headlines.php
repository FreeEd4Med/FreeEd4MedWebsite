<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=UTF-8');
header('Cache-Control: public, max-age=300');

$cachePath = rtrim(sys_get_temp_dir(), DIRECTORY_SEPARATOR) . DIRECTORY_SEPARATOR . 'freeed4med-headlines.json';
$fallbackPath = __DIR__ . '/assets/headlines-fallback.json';
$cacheTtl = 300;
$staleCacheTtl = 86400;
$fallbackTtl = 14 * 24 * 3600;

function respond(array $headlines, int $status = 200): void
{
    http_response_code($status);
    echo json_encode($headlines, JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE);
    exit;
}

function readCachedHeadlines(string $path): ?array
{
    if (!is_file($path) || !is_readable($path)) {
        return null;
    }

    $cached = json_decode((string) file_get_contents($path), true);
    return is_array($cached) && ($cached === [] || isset($cached[0])) ? array_values($cached) : null;
}

$cachedHeadlines = readCachedHeadlines($cachePath);
if ($cachedHeadlines !== null && filemtime($cachePath) >= time() - $cacheTtl) {
    respond($cachedHeadlines);
}

$feeds = [
    'https://news.google.com/rss/search?q=%28music+therapy+OR+music+medicine+OR+music+intervention%29+%28healthcare+OR+clinical+OR+hospital+OR+pain%29&hl=en-US&gl=US&ceid=US:en',
    'https://news.google.com/rss/search?q=%22music+therapy%22+OR+%22music+medicine%22+OR+%22music+and+health%22&hl=en-US&gl=US&ceid=US:en',
    'https://www.sciencedaily.com/rss/mind_brain/music.xml',
];

$context = stream_context_create([
    'http' => [
        'timeout' => 3,
        'user_agent' => 'FreeEd4Med Headlines/1.0 (+https://www.freeed4med.org/)',
        'follow_location' => 1,
        'max_redirects' => 3,
        'ignore_errors' => true,
    ],
    'ssl' => [
        'verify_peer' => true,
        'verify_peer_name' => true,
    ],
]);

$headlines = [];
$successfulFeeds = 0;
$now = time();
foreach ($feeds as $feedUrl) {
    $feedContent = @file_get_contents($feedUrl, false, $context);
    if ($feedContent === false) {
        error_log('FreeEd4Med headlines: RSS source request failed.');
        continue;
    }

    $previousLibxmlSetting = libxml_use_internal_errors(true);
    $rss = simplexml_load_string($feedContent, SimpleXMLElement::class, LIBXML_NONET | LIBXML_NOCDATA);
    libxml_clear_errors();
    libxml_use_internal_errors($previousLibxmlSetting);

    if ($rss === false || !isset($rss->channel->item)) {
        error_log('FreeEd4Med headlines: RSS source returned invalid XML.');
        continue;
    }

    $successfulFeeds++;
    foreach ($rss->channel->item as $item) {
        $title = trim(html_entity_decode(strip_tags((string) $item->title), ENT_QUOTES | ENT_XML1, 'UTF-8'));
        $link = trim((string) $item->link);
        $dateTimestamp = strtotime((string) $item->pubDate);
        $linkParts = parse_url($link);

        if ($title === '' || !is_array($linkParts) || !in_array($linkParts['scheme'] ?? '', ['http', 'https'], true)) {
            continue;
        }

        if ($dateTimestamp !== false && ($dateTimestamp < $now - 30 * 24 * 3600 || $dateTimestamp > $now + 24 * 3600)) {
            continue;
        }

        $key = hash('sha256', strtolower($title));
        $headlines[$key] = [
            'title' => $title,
            'link' => $link,
            'date' => $dateTimestamp === false ? null : date(DATE_ATOM, $dateTimestamp),
            'timestamp' => $dateTimestamp === false ? 0 : $dateTimestamp,
        ];
    }
}

if ($successfulFeeds === 0) {
    if ($cachedHeadlines !== null && is_file($cachePath) && filemtime($cachePath) >= time() - $staleCacheTtl) {
        header('X-Headlines-Source: stale-cache');
        header('Warning: 110 - "Serving stale headline cache"');
        respond($cachedHeadlines);
    }

    $fallbackHeadlines = readCachedHeadlines($fallbackPath);
    if ($fallbackHeadlines !== null) {
        $latestFallbackTimestamp = 0;
        foreach ($fallbackHeadlines as $item) {
            if (!is_array($item) || !is_numeric($item['timestamp'] ?? null)) {
                continue;
            }

            $link = parse_url((string) ($item['link'] ?? ''));
            if (is_array($link) && in_array($link['scheme'] ?? '', ['http', 'https'], true)) {
                $latestFallbackTimestamp = max($latestFallbackTimestamp, (int) $item['timestamp']);
            }
        }
        if ($latestFallbackTimestamp >= time() - $fallbackTtl) {
            header('X-Headlines-Source: bundled-fallback');
            header('X-Headlines-Updated: ' . gmdate(DATE_ATOM, $latestFallbackTimestamp));
            header('Warning: 110 - "Serving bundled headline snapshot"');
            respond($fallbackHeadlines);
        }
    }

    error_log('FreeEd4Med headlines: all RSS sources failed and no cached headlines are available.');
    respond(['error' => 'Headline sources are temporarily unavailable.'], 502);
}

$headlines = array_values($headlines);
usort($headlines, static fn(array $a, array $b): int => $b['timestamp'] <=> $a['timestamp']);
$headlines = array_slice($headlines, 0, 15);

if ($headlines !== []) {
    @file_put_contents($cachePath, json_encode($headlines, JSON_UNESCAPED_SLASHES | JSON_INVALID_UTF8_SUBSTITUTE), LOCK_EX);
}

respond($headlines);
