import Foundation
import WebKit

@MainActor
final class CopyRenderedDOMExtractor: NSObject, WKNavigationDelegate {
    static let shared = CopyRenderedDOMExtractor()

    private lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.preferredContentMode = .desktop
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = self
        return view
    }()

    private var navigationContinuation: CheckedContinuation<Void, Error>?
    private var isLoading = false

    private struct RenderedItem: Decodable {
        let id: String
        let title: String
        let group: String
    }

    private struct RenderedPayload: Decodable {
        let loading: Bool
        let items: [RenderedItem]
    }

    func fetchChapters(comicURL: URL, slug: String, cookie: String?, baselineCount: Int) async -> [ComicChapter] {
        do {
            try await load(url: comicURL, cookie: cookie, timeout: 10)
            return try await pollChapters(slug: slug, baselineCount: baselineCount, timeout: 10)
        } catch {
            return []
        }
    }

    private func load(url: URL, cookie: String?, timeout: TimeInterval) async throws {
        if isLoading {
            webView.stopLoading()
            navigationContinuation = nil
            isLoading = false
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        if let cookie, !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        isLoading = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            navigationContinuation = continuation
            webView.load(request)

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(Int(timeout * 1000)))
                if self.isLoading, let pending = self.navigationContinuation {
                    self.navigationContinuation = nil
                    self.isLoading = false
                    self.webView.stopLoading()
                    pending.resume(throwing: URLError(.timedOut))
                }
            }
        }
    }

    private func pollChapters(slug: String, baselineCount: Int, timeout: TimeInterval) async throws -> [ComicChapter] {
        let start = Date()
        var best: [ComicChapter] = []

        while Date().timeIntervalSince(start) < timeout {
            let payload = try await evaluateChapterPayload(slug: slug)
            let parsed = decodeChapters(from: payload)
            if parsed.count > best.count {
                best = parsed
            }

            let goodEnough = parsed.count > max(10, baselineCount + 5)
            if goodEnough || (!payload.loading && parsed.count > 0) {
                break
            }
            try await Task.sleep(for: .milliseconds(350))
        }

        return best
    }

    private func evaluateChapterPayload(slug: String) async throws -> RenderedPayload {
        let escapedSlug = slug.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        (() => {
          const slug = "\(escapedSlug)";
          const docRoot = document;

          const collectFromScope = (scope, groupName) => {
            const byID = new Map();
            const anchors = Array.from(scope.querySelectorAll(`a[href*="/comic/${slug}/chapter/"]`));
            for (const a of anchors) {
              const href = a.getAttribute('href') || '';
              const m = href.match(/\\/chapter\\/([^\\/?#]+)/);
              if (!m || !m[1]) continue;
              const id = m[1].trim();
              if (!id || byID.has(id)) continue;
              const title = (a.getAttribute('title') || a.textContent || '').trim();
              byID.set(id, { id, title, group: groupName });
            }
            return Array.from(byID.values());
          };

          const normalizeText = (text) => (text || '').trim().replace(/\\s+/g, ' ');

          const readTitleText = (el) => {
            if (!el) return '';
            return normalizeText(el.textContent || '');
          };

          const isAllTabLabel = (text) => {
            const normalized = normalizeText(text);
            if (!normalized) return false;
            const folded = normalized.toLowerCase();
            return (
              normalized === '全部' ||
              normalized === '全部章节' ||
              normalized === '全部章節' ||
              folded === 'all' ||
              folded === 'all chapter' ||
              folded === 'all chapters'
            );
          };

          const isGenericGroupName = (text) => {
            const normalized = normalizeText(text);
            if (!normalized) return true;
            const folded = normalized.toLowerCase();
            if (
              [
                '默认', '默認', 'default',
                '全部', 'all',
                '話', '话',
                '卷',
                '番外', '番外篇',
                '章节', '章節',
                '目录', '目錄'
              ].includes(normalized)
            ) {
              return true;
            }
            if (folded === 'default' || folded === 'all') return true;
            return /^分类\\d+$/.test(normalized) || /^分類\\d+$/.test(normalized);
          };

          const buildTabGroupName = (baseGroupName, tabLabel) => {
            const base = normalizeText(baseGroupName);
            const label = normalizeText(tabLabel);
            if (!label || isAllTabLabel(label)) {
              return base || '默认';
            }
            if (!base || isGenericGroupName(base)) {
              return label;
            }
            return `${base} · ${label}`;
          };

          const findAllPane = (scope) => {
            const panes = Array.from(scope.querySelectorAll('.tab-pane'));
            return panes.find((pane) => {
              const id = normalizeText(pane.id || '');
              if (!id) return false;
              const folded = id.toLowerCase();
              return id.endsWith('全部') || id.includes('全部') || folded.endsWith('all') || folded.includes('all');
            });
          };

          const collectFromTabbedScope = (scope, baseGroupName) => {
            if (!scope) return [];

            const descriptors = [];
            const seenPaneKeys = new Set();
            const links = Array.from(scope.querySelectorAll('a[data-toggle="tab"], .nav-link[data-toggle="tab"], [role="tab"]'));
            for (const link of links) {
              const label = readTitleText(link);
              const targetRaw = (link.getAttribute('href') || link.getAttribute('data-target') || '').trim();
              const controls = (link.getAttribute('aria-controls') || '').trim();
              let pane = null;
              if (targetRaw.startsWith('#')) {
                pane = scope.querySelector(targetRaw) || docRoot.querySelector(targetRaw);
              }
              if (!pane && controls) {
                const target = `#${controls}`;
                pane = scope.querySelector(target) || docRoot.querySelector(target);
              }
              if (!pane) continue;
              const key = pane.id || `${label}::${descriptors.length}`;
              if (seenPaneKeys.has(key)) continue;
              seenPaneKeys.add(key);
              descriptors.push({ pane, label });
            }

            if (descriptors.length === 0) {
              const panes = Array.from(scope.querySelectorAll('.tab-pane'));
              panes.forEach((pane, idx) => descriptors.push({ pane, label: idx === 0 ? '全部' : `分类${idx + 1}` }));
            }

            if (descriptors.length === 0) return [];

            const tabItems = [];
            let allItems = [];
            for (const descriptor of descriptors) {
              const groupName = buildTabGroupName(baseGroupName, descriptor.label);
              const paneItems = collectFromScope(descriptor.pane, groupName);
              if (paneItems.length === 0) continue;
              if (isAllTabLabel(descriptor.label)) {
                allItems = paneItems;
              } else {
                tabItems.push(...paneItems);
              }
            }

            if (tabItems.length > 0) return tabItems;
            return allItems;
          };

          const inferGroupName = (tableEl, index) => {
            // First check if the tableEl itself is a title container
            const selfTitle = readTitleText(tableEl);
            if (selfTitle && tableEl.classList && tableEl.classList.contains('table-default-title')) {
              return selfTitle;
            }

            // Check the immediately preceding sibling for a title
            const immediateTitle = readTitleText(
              tableEl.previousElementSibling &&
              tableEl.previousElementSibling.classList &&
              tableEl.previousElementSibling.classList.contains('table-default-title')
                ? tableEl.previousElementSibling
                : null
            );
            if (immediateTitle) {
              return immediateTitle;
            }

            // Walk siblings backwards looking for a title
            let cursor = tableEl.previousElementSibling;
            while (cursor) {
              if (cursor.classList && cursor.classList.contains('table-default')) break;
              const text = readTitleText(cursor);
              if (text) {
                // Only exclude navigation/meta UI text – NOT actual volume/extra names like "第一卷", "番外篇"
                const looksMeta = text.includes('更新') || text.includes('跳转') || text.includes('GO');
                // Only skip standalone generic tab-bar labels (exact matches), not real volume group names
                const normalized = text.trim();
                const folded = normalized.toLowerCase();
                const isGenericTabLabel = ['全部', '話', '话', '卷', '番外'].includes(normalized) || folded === 'all';
                if (!looksMeta && !isGenericTabLabel && text.length <= 30) {
                  return text;
                }
              }
              cursor = cursor.previousElementSibling;
            }
            return index === 0 ? '默认' : `分类${index + 1}`;
          };

          const items = [];
          const tableBlocks = Array.from(docRoot.querySelectorAll('.table-default'));
          if (tableBlocks.length > 0) {
            tableBlocks.forEach((block, index) => {
              const groupName = inferGroupName(block, index);
              const fromTabs = collectFromTabbedScope(block, groupName);
              if (fromTabs.length > 0) {
                items.push(...fromTabs);
                return;
              }
              const allPane = findAllPane(block);
              const activePane = block.querySelector('.tab-pane.show.active');
              const preferredScope = allPane || activePane || block;
              items.push(...collectFromScope(preferredScope, groupName));
            });
          }

          if (items.length === 0) {
            const right = docRoot.querySelector('.comicParticulars-right') || docRoot;
            const sectionTitles = Array.from(right.querySelectorAll('.table-default-title'));
            if (sectionTitles.length > 0) {
              sectionTitles.forEach((titleEl, index) => {
                const titleText = readTitleText(titleEl);
                const groupName = titleText || inferGroupName(titleEl, index);
                let box = titleEl.nextElementSibling;
                while (box) {
                  if (box.classList && (box.classList.contains('table-default-box') || box.classList.contains('table-default'))) break;
                  if (box.classList && box.classList.contains('table-default-title')) break;
                  box = box.nextElementSibling;
                }
                const sectionScope = box && !(box.classList && box.classList.contains('table-default-title')) ? box : null;
                if (!sectionScope) return;
                const fromTabs = collectFromTabbedScope(sectionScope, groupName);
                if (fromTabs.length > 0) {
                  items.push(...fromTabs);
                  return;
                }
                const allPane = findAllPane(sectionScope);
                const preferredScope = allPane || sectionScope;
                items.push(...collectFromScope(preferredScope, groupName));
              });
            }
          }

          if (items.length === 0) {
            const byID = new Map();
            const anchors = Array.from(docRoot.querySelectorAll(`a[href*="/comic/${slug}/chapter/"]`));
            for (const a of anchors) {
              const href = a.getAttribute('href') || '';
              const m = href.match(/\\/chapter\\/([^\\/?#]+)/);
              if (!m || !m[1]) continue;
              const id = m[1].trim();
              if (!id || byID.has(id)) continue;
              const title = (a.getAttribute('title') || a.textContent || '').trim();
              byID.set(id, { id, title, group: '默认' });
            }
            items.push(...Array.from(byID.values()));
          }

          const text = docRoot.textContent || '';
          const loading = text.includes('章節加載中') || text.includes('章节加載中') || text.includes('章节加载中');
          return JSON.stringify({ loading, items });
        })();
        """

        let text = try await evaluateJavaScriptString(script)
        guard let data = text.data(using: .utf8) else {
            throw URLError(.cannotParseResponse)
        }
        return try JSONDecoder().decode(RenderedPayload.self, from: data)
    }

    private func decodeChapters(from payload: RenderedPayload) -> [ComicChapter] {
        var seen: Set<String> = []
        var output: [ComicChapter] = []
        for (idx, item) in payload.items.enumerated() {
            let id = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if id.isEmpty || !seen.insert(id).inserted { continue }
            let name = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let groupName = canonicalGroupName(item.group)
            output.append(
                ComicChapter(
                    id: id,
                    uuid: id,
                    displayName: name.isEmpty ? id : name,
                    order: Double(idx),
                    volumeID: groupName,
                    volumeName: groupName
                )
            )
        }
        return output
    }

    private func evaluateJavaScriptString(_ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            webView.evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let text = value as? String {
                    continuation.resume(returning: text)
                } else {
                    continuation.resume(throwing: URLError(.cannotParseResponse))
                }
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        navigationContinuation?.resume()
        navigationContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }
}
