# Third-Party Vendor Database Reference

## Vendor Categories and Domain Mappings

### Analytics

Track user behavior, page views, and conversions.

| Domain Pattern | Vendor | Blocking | Typical Size |
|---------------|--------|----------|-------------|
| `google-analytics.com` | Google Analytics | No (async) | 20-45 KB |
| `googletagmanager.com` | Google Tag Manager | Yes (often) | 30-80 KB |
| `segment.com`, `cdn.segment.com` | Segment | No (async) | 30-70 KB |
| `mixpanel.com`, `cdn.mxpnl.com` | Mixpanel | No (async) | 20-40 KB |
| `amplitude.com`, `cdn.amplitude.com` | Amplitude | No (async) | 25-50 KB |
| `hotjar.com`, `static.hotjar.com` | Hotjar | No (async) | 30-60 KB |
| `clarity.ms` | Microsoft Clarity | No (async) | 15-30 KB |
| `plausible.io` | Plausible | No (async) | 1-2 KB |
| `matomo.cloud` | Matomo | No (async) | 20-40 KB |
| `heap.io`, `heapanalytics.com` | Heap | No (async) | 40-80 KB |
| `fullstory.com` | FullStory | No (async) | 40-70 KB |
| `mouseflow.com` | Mouseflow | No (async) | 25-50 KB |

### Advertising

Ad networks, retargeting pixels, and conversion tracking.

| Domain Pattern | Vendor | Blocking | Typical Size |
|---------------|--------|----------|-------------|
| `doubleclick.net` | Google Ads | Yes | 30-100+ KB |
| `googlesyndication.com` | Google AdSense | Yes | 50-150+ KB |
| `googleadservices.com` | Google Ads Conversion | No (pixel) | 1-5 KB |
| `connect.facebook.net/en_US/fbevents.js` | Meta Pixel | No (async) | 20-50 KB |
| `facebook.net/tr` | Meta Tracking Pixel | No (pixel) | 1-2 KB |
| `adnxs.com` | Xandr (AppNexus) | No | 10-30 KB |
| `criteo.com`, `criteo.net` | Criteo | No | 15-40 KB |
| `ads-twitter.com` | Twitter/X Ads | No (pixel) | 5-15 KB |
| `snap.licdn.com` | LinkedIn Insight | No (pixel) | 5-15 KB |
| `tiktok.com/i18n/pixel` | TikTok Pixel | No (async) | 10-30 KB |
| `amazon-adsystem.com` | Amazon Ads | Yes | 20-60 KB |
| `adsrvr.org` | The Trade Desk | No | 5-15 KB |
| `rubiconproject.com` | Magnite (Rubicon) | No | 10-25 KB |

### Social Widgets

Social media embeds, share buttons, and login integrations.

| Domain Pattern | Vendor | Blocking | Typical Size |
|---------------|--------|----------|-------------|
| `connect.facebook.net` | Facebook SDK | Yes (if sync) | 50-150 KB |
| `platform.twitter.com` | Twitter/X Widgets | Yes (iframes) | 30-80 KB |
| `platform.linkedin.com` | LinkedIn Widgets | No | 20-50 KB |
| `apis.google.com` | Google Sign-In / +1 | Yes (if sync) | 30-80 KB |
| `platform.instagram.com` | Instagram Embeds | Yes (iframes) | 50-200 KB |
| `player.vimeo.com` | Vimeo Embeds | Yes (iframes) | 40-100 KB |
| `youtube.com/embed` | YouTube Embeds | Yes (iframes) | 50-200+ KB |
| `disqus.com` | Disqus Comments | Yes | 100-300 KB |
| `addthis.com` | AddThis Share Buttons | Yes | 50-100 KB |
| `sharethrough.com` | Sharethrough | No | 10-30 KB |

### CDN and Libraries

Content delivery networks and shared JavaScript/CSS libraries.

| Domain Pattern | Vendor | Blocking | Typical Size |
|---------------|--------|----------|-------------|
| `cdnjs.cloudflare.com` | Cloudflare CDN | Yes (usually sync) | Varies |
| `cdn.jsdelivr.net` | jsDelivr | Yes (usually sync) | Varies |
| `unpkg.com` | unpkg | Yes (usually sync) | Varies |
| `ajax.googleapis.com` | Google Hosted Libraries | Yes (usually sync) | 30-90 KB |
| `code.jquery.com` | jQuery CDN | Yes (sync) | 30-90 KB |
| `stackpath.bootstrapcdn.com` | Bootstrap CDN | Yes (sync) | 20-60 KB |
| `cdn.tailwindcss.com` | Tailwind CDN | Yes (sync) | 50-300 KB |
| `cdn.shopify.com` | Shopify CDN | Yes | Varies |
| `assets.adobedtm.com` | Adobe DTM/Launch | Yes | 30-100 KB |

### Fonts

Web font loading services.

| Domain Pattern | Vendor | Blocking | Typical Size |
|---------------|--------|----------|-------------|
| `fonts.googleapis.com` | Google Fonts CSS | Yes (render-blocking) | 1-5 KB |
| `fonts.gstatic.com` | Google Fonts Files | Yes (font files) | 10-50 KB per font |
| `use.typekit.net` | Adobe Fonts (Typekit) | Yes (render-blocking) | 5-20 KB + fonts |
| `fast.fonts.net` | Monotype | Yes | 10-40 KB per font |
| `use.fontawesome.com` | Font Awesome | Yes (CSS + fonts) | 30-100 KB |
| `kit.fontawesome.com` | Font Awesome Kit | Yes | 30-80 KB |
| `fonts.bunny.net` | Bunny Fonts (GDPR) | Yes | 10-50 KB per font |

### Tag Managers

Orchestrate other third-party scripts.

| Domain Pattern | Vendor | Blocking | Typical Size |
|---------------|--------|----------|-------------|
| `googletagmanager.com` | Google Tag Manager | Yes (often) | 30-80 KB + injected tags |
| `tags.tiqcdn.com`, `tealium.com` | Tealium | Yes | 30-100 KB |
| `cdn.segment.com/analytics.js` | Segment | No (async) | 30-70 KB |
| `rum-static.pingdom.net` | Pingdom RUM | No | 10-20 KB |
| `cdn.cookielaw.org` | OneTrust (consent) | Yes (often) | 30-80 KB |
| `consent.cookiebot.com` | Cookiebot (consent) | Yes (often) | 20-50 KB |

### Performance Monitoring / APM

Real user monitoring and application performance.

| Domain Pattern | Vendor | Blocking | Typical Size |
|---------------|--------|----------|-------------|
| `js-agent.newrelic.com`, `bam.nr-data.net` | New Relic | No (async) | 15-40 KB |
| `browser-intake-datadoghq.com` | Datadog RUM | No (async) | 20-50 KB |
| `browser.sentry-cdn.com`, `sentry.io` | Sentry | No (async) | 20-60 KB |
| `rum.hlx.page` | Adobe RUM | No (async) | 5-15 KB |
| `cdn.speedcurve.com` | SpeedCurve LUX | No (async) | 10-25 KB |
| `d2wy8f7a9ursnm.cloudfront.net` | Bugsnag | No (async) | 15-30 KB |
| `cdn.raygun.io` | Raygun | No (async) | 15-35 KB |

### Customer Support / Chat

Live chat widgets, help centers, and chatbots.

| Domain Pattern | Vendor | Blocking | Typical Size |
|---------------|--------|----------|-------------|
| `widget.intercom.io`, `js.intercomcdn.com` | Intercom | No (async) | 50-200 KB |
| `js.driftt.com` | Drift | No (async) | 40-150 KB |
| `embed.tawk.to` | Tawk.to | No (async) | 30-100 KB |
| `static.zdassets.com` | Zendesk | No (async) | 50-150 KB |
| `wchat.freshchat.com` | Freshchat | No (async) | 40-120 KB |
| `cdn.livechatinc.com` | LiveChat | No (async) | 30-100 KB |
| `static.hsappstatic.net` | HubSpot Chat | No (async) | 40-120 KB |
| `crisp.chat` | Crisp | No (async) | 30-100 KB |

## Impact Scoring Methodology

### Request Classification

| Property | How to Determine |
|----------|-----------------|
| **Blocking** | Request initiated by `<script>` without `async`/`defer`, or `<link rel="stylesheet">` in `<head>` |
| **Non-blocking** | Request initiated by `async`/`defer` script, `<img>`, XHR/fetch, or dynamically injected |
| **Render-blocking** | Resource that appears in the critical rendering path (blocks first paint) |

### Impact Score Calculation (per vendor)

```
Impact Score = (Blocking Weight + Size Weight + Request Count Weight + Failure Risk) / 4
```

**Blocking Weight (0-100):**

| Classification | Score |
|---------------|-------|
| Render-blocking (sync script/CSS in head) | 100 |
| Parser-blocking (sync script in body) | 75 |
| Layout-blocking (font loading) | 50 |
| Non-blocking (async, images, pixels) | 10 |
| Pixel/beacon (1x1, < 2KB) | 5 |

**Size Weight (0-100):**

| Transfer Size | Score |
|--------------|-------|
| > 200 KB | 100 |
| 100-200 KB | 75 |
| 50-100 KB | 50 |
| 20-50 KB | 25 |
| < 20 KB | 10 |

**Request Count Weight (0-100):**

| Requests from Vendor | Score |
|---------------------|-------|
| > 20 requests | 100 |
| 10-20 requests | 75 |
| 5-10 requests | 50 |
| 2-5 requests | 25 |
| 1 request | 10 |

**Failure Risk (0-100):**

| Factor | Score Addition |
|--------|--------------|
| Single point of failure (no fallback) | +30 |
| Known for outages | +20 |
| Cross-origin with no CORS fallback | +15 |
| DNS resolution required | +10 |
| Uses document.write | +25 |

### Overall Third-Party Health Grade

| Grade | Criteria |
|-------|----------|
| **A** | Total third-party < 100 KB, no render-blocking, < 5 vendors |
| **B** | Total third-party < 250 KB, <= 1 render-blocking, < 10 vendors |
| **C** | Total third-party < 500 KB, <= 3 render-blocking, < 15 vendors |
| **D** | Total third-party < 1 MB, multiple render-blocking |
| **F** | Total third-party > 1 MB or > 5 render-blocking resources |

### Vendor Identification Algorithm

1. Extract hostname from request URL
2. Strip `www.` prefix
3. Match against domain patterns (exact match first, then suffix match)
4. If no match found, categorize as "Unknown" with the base domain as vendor name
5. Group all requests from same vendor
6. Calculate aggregate impact score per vendor
