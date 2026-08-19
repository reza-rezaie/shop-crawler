import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import './App.css'

const PAGE_SIZE = 24
const PROGRESS_POLL_MS = 600

async function apiGet(path) {
  const res = await fetch(path)
  if (!res.ok) throw new Error(`Request failed: ${res.status}`)
  return res.json()
}

async function apiPost(path, body) {
  const res = await fetch(path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
  if (!res.ok) throw new Error(`Request failed: ${res.status}`)
  return res.json()
}

// Polls /api/progress while a crawl or discovery run is in flight. The
// backend only ever tracks one run at a time (see server.py's
// CURRENT_PROGRESS) -- each caller of this hook just watches it during its
// own request and ignores it otherwise.
function useProgressPolling() {
  const [progress, setProgress] = useState(null)
  const intervalRef = useRef(null)

  const start = useCallback(() => {
    setProgress(null)
    const poll = async () => {
      try {
        setProgress(await apiGet('/api/progress'))
      } catch {
        // Non-fatal: the progress display just stops updating until the
        // next tick succeeds: the crawl/discovery request itself is what
        // actually reports success or failure.
      }
    }
    poll()
    intervalRef.current = setInterval(poll, PROGRESS_POLL_MS)
  }, [])

  const stop = useCallback(() => {
    if (intervalRef.current) {
      clearInterval(intervalRef.current)
      intervalRef.current = null
    }
  }, [])

  // Stop polling on unmount too, not just when the caller remembers to.
  useEffect(() => stop, [stop])

  return { progress, start, stop }
}

function ProgressBar({ progress, kind }) {
  if (!progress) return null

  if (progress.phase === 'details') {
    const total = progress.detail_total || 0
    const index = Math.min(progress.detail_index || 0, total)
    const pct = total > 0 ? Math.round((index / total) * 100) : 0
    return (
      <div className="progress-block">
        <div className="progress-bar">
          <div className="progress-fill" style={{ width: `${pct}%` }} />
        </div>
        <div className="progress-label">
          Fetching product details… {index} / {total}
        </div>
      </div>
    )
  }

  const total = progress.pages_total || 0
  const visited = Math.min(progress.pages_visited || 0, total)
  const pct = total > 0 ? Math.round((visited / total) * 100) : 0
  const foundLabel =
    kind === 'discover'
      ? `${progress.categories_found || 0} categor${(progress.categories_found || 0) === 1 ? 'y' : 'ies'} found so far`
      : `${progress.products_found || 0} product${(progress.products_found || 0) === 1 ? '' : 's'} found so far`

  return (
    <div className="progress-block">
      <div className="progress-bar">
        <div className="progress-fill" style={{ width: `${pct}%` }} />
      </div>
      <div className="progress-label">
        Page {visited} / {total} — {foundLabel}
      </div>
    </div>
  )
}

function formatPrice(price, currency) {
  if (price === null || price === undefined) return 'Price unknown'
  const symbol = currency && currency.length <= 3 ? currency : ''
  return `${symbol}${price.toFixed(2)}${!symbol && currency ? ` ${currency}` : ''}`
}

function signalLabel(hasOwnProducts) {
  if (hasOwnProducts === null || hasOwnProducts === undefined) return 'Products: unknown'
  return hasOwnProducts ? 'Products: yes' : 'Products: no'
}

function signalClass(hasOwnProducts) {
  if (hasOwnProducts === null || hasOwnProducts === undefined) return 'unknown'
  return hasOwnProducts ? 'yes' : 'no'
}

// Turns the flat list `/api/site-categories` returns into a parent -> children
// map, so the tree can be rendered recursively without the server needing to
// nest the JSON itself. A node whose parent_url isn't in this same list (root
// of the tree, or its parent fell outside a host filter/budget cutoff) is
// treated as a root -- otherwise a budget-truncated discovery run could leave
// an orphaned node unrenderable instead of just showing it at the top level.
function buildCategoryForest(nodes) {
  const byUrl = new Map(nodes.map((n) => [n.url, n]))
  const childrenByParent = new Map()
  const roots = []
  for (const node of nodes) {
    const parent = node.parent_url
    if (parent && byUrl.has(parent)) {
      if (!childrenByParent.has(parent)) childrenByParent.set(parent, [])
      childrenByParent.get(parent).push(node)
    } else {
      roots.push(node)
    }
  }
  return { roots, childrenByParent }
}

function CategoryTreeNode({ node, childrenByParent }) {
  const children = childrenByParent.get(node.url) || []
  return (
    <li className="category-node">
      <div className="category-node-row">
        <a href={node.url} target="_blank" rel="noreferrer">
          {node.name}
        </a>
        <span className={`product-signal ${signalClass(node.has_own_products)}`}>
          {signalLabel(node.has_own_products)}
        </span>
      </div>
      {children.length > 0 && (
        <ul>
          {children.map((child) => (
            <CategoryTreeNode key={child.id} node={child} childrenByParent={childrenByParent} />
          ))}
        </ul>
      )}
    </li>
  )
}

function CategoryTree({ nodes }) {
  const { roots, childrenByParent } = useMemo(() => buildCategoryForest(nodes), [nodes])
  return (
    <ul className="category-tree">
      {roots.map((node) => (
        <CategoryTreeNode key={node.id} node={node} childrenByParent={childrenByParent} />
      ))}
    </ul>
  )
}

function CategoriesView() {
  const [discoveryUrl, setDiscoveryUrl] = useState('')
  const [maxPages, setMaxPages] = useState(25)
  const [discovering, setDiscovering] = useState(false)
  const [discoveryStatus, setDiscoveryStatus] = useState(null) // {type, message}
  const [discoveryNotes, setDiscoveryNotes] = useState([])
  const { progress, start: startProgress, stop: stopProgress } = useProgressPolling()

  const [host, setHost] = useState('')
  const [tree, setTree] = useState([])
  const [treeLoading, setTreeLoading] = useState(false)
  const [treeError, setTreeError] = useState(null)
  const [treeLoaded, setTreeLoaded] = useState(false)

  const loadTree = useCallback(async (targetHost) => {
    if (!targetHost) return
    setTreeLoading(true)
    setTreeError(null)
    try {
      const params = new URLSearchParams({ host: targetHost })
      const nodes = await apiGet(`/api/site-categories?${params.toString()}`)
      setTree(nodes)
      setTreeLoaded(true)
    } catch (err) {
      setTreeError(err.message)
    } finally {
      setTreeLoading(false)
    }
  }, [])

  const handleViewHost = (e) => {
    e.preventDefault()
    if (!host.trim()) return
    loadTree(host.trim())
  }

  const handleDiscover = async (e) => {
    e.preventDefault()
    if (!discoveryUrl.trim()) return
    setDiscovering(true)
    setDiscoveryStatus({ type: 'info', message: 'Discovering categories... this can take a while, especially if pages need JavaScript rendering.' })
    setDiscoveryNotes([])
    startProgress()
    try {
      const result = await apiPost('/api/site-categories/discover', {
        url: discoveryUrl.trim(),
        max_pages: Number(maxPages) || 25,
      })
      if (result.error) {
        setDiscoveryStatus({ type: 'error', message: result.error })
      } else {
        const errSuffix = result.errors && result.errors.length
          ? ` (${result.errors.length} warning${result.errors.length > 1 ? 's' : ''})`
          : ''
        setDiscoveryStatus({
          type: result.categories_found === 0 && result.categories_updated === 0 ? 'warning' : 'success',
          message: `Visited ${result.pages_visited} page(s): ${result.categories_found} new, ${result.categories_updated} updated categor${result.categories_updated === 1 ? 'y' : 'ies'}${errSuffix}.`,
        })
        setDiscoveryNotes(result.notes || [])
        let discoveredHost = ''
        try {
          discoveredHost = new URL(discoveryUrl.trim()).host
        } catch {
          // Invalid URL would have already failed the discovery request itself.
        }
        if (discoveredHost) {
          setHost(discoveredHost)
          await loadTree(discoveredHost)
        }
      }
    } catch (err) {
      setDiscoveryStatus({ type: 'error', message: err.message })
    } finally {
      stopProgress()
      setDiscovering(false)
    }
  }

  return (
    <>
      <form className="crawl-panel" onSubmit={handleDiscover}>
        <div className="crawl-row">
          <input
            type="url"
            required
            placeholder="https://example-shop.com/shop/category"
            value={discoveryUrl}
            onChange={(e) => setDiscoveryUrl(e.target.value)}
          />
          <button className="btn" type="submit" disabled={discovering}>
            {discovering ? 'Discovering…' : 'Discover categories'}
          </button>
        </div>
        <div className="crawl-options">
          <label>
            Max pages
            <input
              type="number"
              min="1"
              max="200"
              value={maxPages}
              onChange={(e) => setMaxPages(e.target.value)}
            />
          </label>
          <span>Finds a site's category tree ahead of crawling it for products. Re-running fills in more of an already-started tree.</span>
        </div>
        {discovering && <ProgressBar progress={progress} kind="discover" />}
        {discoveryStatus && (
          <div className={`crawl-status ${discoveryStatus.type}`}>{discoveryStatus.message}</div>
        )}
        {discoveryNotes.length > 0 && (
          <ul className="crawl-notes">
            {discoveryNotes.map((note, i) => (
              <li key={i}>{note}</li>
            ))}
          </ul>
        )}
      </form>

      <form className="filters" onSubmit={handleViewHost}>
        <input
          type="text"
          placeholder="Host, e.g. example-shop.com"
          value={host}
          onChange={(e) => setHost(e.target.value)}
        />
        <button className="btn secondary" type="submit" disabled={treeLoading}>
          View tree
        </button>
      </form>

      <div className="result-meta">
        {treeLoading
          ? 'Loading…'
          : treeError
            ? `Failed to load categories: ${treeError}`
            : treeLoaded
              ? `${tree.length} categor${tree.length === 1 ? 'y' : 'ies'} discovered for ${host}`
              : 'Discover a site above, or enter a host to view a previously discovered tree.'}
      </div>

      {treeLoaded && !treeLoading && !treeError && tree.length === 0 && (
        <div className="empty-state">No categories discovered yet for this host.</div>
      )}

      {tree.length > 0 && <CategoryTree nodes={tree} />}
    </>
  )
}

function ProductCard({ product }) {
  return (
    <a
      className="product-card"
      href={product.product_url}
      target="_blank"
      rel="noreferrer"
    >
      <div className="product-body">
        {product.source_host && (
          <div className="product-source" title="Crawled from this site">
            {product.source_host}
          </div>
        )}
        <div className="product-name">{product.name}</div>
        {product.category && (
          <div className="product-category">{product.category}</div>
        )}
        <div className="product-price">
          {formatPrice(product.price, product.currency)}
        </div>
      </div>
    </a>
  )
}

export default function App() {
  const [view, setView] = useState('products') // 'products' | 'categories'

  const [crawlUrl, setCrawlUrl] = useState('')
  const [maxPages, setMaxPages] = useState(3)
  const [fetchDescriptions, setFetchDescriptions] = useState(true)
  const [crawling, setCrawling] = useState(false)
  const [crawlStatus, setCrawlStatus] = useState(null) // {type, message}
  const [crawlNotes, setCrawlNotes] = useState([])
  const { progress: crawlProgress, start: startCrawlProgress, stop: stopCrawlProgress } = useProgressPolling()

  const [search, setSearch] = useState('')
  const [category, setCategory] = useState('')
  const [sourceHost, setSourceHost] = useState('')
  const [minPrice, setMinPrice] = useState('')
  const [maxPrice, setMaxPrice] = useState('')
  const [page, setPage] = useState(1)

  const [categories, setCategories] = useState([])
  const [sources, setSources] = useState([])
  const [items, setItems] = useState([])
  const [total, setTotal] = useState(0)
  const [loading, setLoading] = useState(false)
  const [loadError, setLoadError] = useState(null)

  const loadCategories = useCallback(async () => {
    try {
      const cats = await apiGet('/api/categories')
      setCategories(cats)
    } catch {
      // Non-fatal: filter dropdown just stays empty.
    }
  }, [])

  const loadSources = useCallback(async () => {
    try {
      const srcs = await apiGet('/api/sources')
      setSources(srcs)
    } catch {
      // Non-fatal: filter dropdown just stays empty.
    }
  }, [])

  // Accepts an optional overrides object so a caller (handleCrawl) can fetch
  // with a filter value it just computed without waiting for that value to
  // land in state first. Without this, calling setSourceHost(...) and then
  // loadProducts() back-to-back is a race: this function's own closure still
  // has the *old* sourceHost, so it can fetch and overwrite the display with
  // stale unfiltered results *after* the state-driven effect's fresh fetch
  // resolves, depending on which network request happens to finish last.
  const loadProducts = useCallback(async (overrides = {}) => {
    const effective = {
      search,
      category,
      sourceHost,
      minPrice,
      maxPrice,
      page,
      ...overrides,
    }
    setLoading(true)
    setLoadError(null)
    try {
      const params = new URLSearchParams()
      if (effective.search) params.set('search', effective.search)
      if (effective.category) params.set('category', effective.category)
      if (effective.sourceHost) params.set('source_host', effective.sourceHost)
      if (effective.minPrice) params.set('min_price', effective.minPrice)
      if (effective.maxPrice) params.set('max_price', effective.maxPrice)
      params.set('page', String(effective.page))
      params.set('page_size', String(PAGE_SIZE))
      const data = await apiGet(`/api/products?${params.toString()}`)
      setItems(data.items)
      setTotal(data.total)
    } catch (err) {
      setLoadError(err.message)
    } finally {
      setLoading(false)
    }
  }, [search, category, sourceHost, minPrice, maxPrice, page])

  useEffect(() => {
    loadCategories()
    loadSources()
  }, [loadCategories, loadSources])

  useEffect(() => {
    loadProducts()
  }, [loadProducts])

  // Reset to page 1 whenever a filter changes.
  useEffect(() => {
    setPage(1)
  }, [search, category, sourceHost, minPrice, maxPrice])

  const handleCrawl = async (e) => {
    e.preventDefault()
    if (!crawlUrl.trim()) return
    setCrawling(true)
    setCrawlStatus({ type: 'info', message: 'Crawling... this can take a while depending on page/product count.' })
    setCrawlNotes([])
    startCrawlProgress()
    try {
      const result = await apiPost('/api/crawl', {
        url: crawlUrl.trim(),
        max_pages: Number(maxPages) || 3,
        fetch_descriptions: fetchDescriptions,
      })
      if (result.error) {
        setCrawlStatus({ type: 'error', message: result.error })
      } else {
        const errSuffix = result.errors && result.errors.length
          ? ` (${result.errors.length} warning${result.errors.length > 1 ? 's' : ''})`
          : ''
        setCrawlStatus({
          type: result.products_found === 0 ? 'warning' : 'success',
          message: `Crawled ${result.pages_crawled} page(s): ${result.products_created} new, ${result.products_updated} updated (${result.products_found} total found)${errSuffix}.`,
        })
        setCrawlNotes(result.notes || [])
        // Narrow the browse view to the site just crawled. Without this,
        // whatever was already in the catalog from an earlier crawl of a
        // different site stays visible under the "All sites" filter,
        // which reads as "I crawled X but it's showing Y" even though Y
        // is just older, unrelated data.
        let crawledHost = ''
        try {
          crawledHost = new URL(crawlUrl.trim()).host
        } catch {
          // Invalid URL would have already been rejected by the crawl
          // request itself; nothing to narrow to in that case.
        }
        if (crawledHost) {
          setSourceHost(crawledHost)
          setPage(1)
        }
        await loadCategories()
        await loadSources()
        // Pass the freshly computed host explicitly rather than relying on
        // `sourceHost` state (see loadProducts' comment for why).
        await loadProducts({ sourceHost: crawledHost || sourceHost, page: 1 })
      }
    } catch (err) {
      setCrawlStatus({ type: 'error', message: err.message })
    } finally {
      stopCrawlProgress()
      setCrawling(false)
    }
  }

  const totalPages = useMemo(
    () => Math.max(1, Math.ceil(total / PAGE_SIZE)),
    [total],
  )

  // Include the currently-applied source filter even if it isn't in
  // `sources` yet (a site that was just crawled but yielded zero products
  // has no rows to be "distinct" over, so /api/sources never lists it).
  // Without this the dropdown would silently fall back to "All sites"
  // while a filter is actually still applied, which is exactly the kind
  // of "why am I not seeing what I expect" mismatch this filter exists to
  // prevent.
  const sourceOptions = useMemo(() => {
    if (!sourceHost || sources.includes(sourceHost)) return sources
    return [...sources, sourceHost].sort()
  }, [sources, sourceHost])

  return (
    <div className="app">
      <header className="app-header">
        <h1>Mojo Product Crawler</h1>
        <p className="subtitle">
          Native-Mojo crawler + SQLite catalog, browsable locally.
        </p>
      </header>

      <nav className="view-tabs">
        <button
          type="button"
          className={`tab ${view === 'products' ? 'active' : ''}`}
          onClick={() => setView('products')}
        >
          Browse products
        </button>
        <button
          type="button"
          className={`tab ${view === 'categories' ? 'active' : ''}`}
          onClick={() => setView('categories')}
        >
          Categories
        </button>
      </nav>

      {view === 'categories' && <CategoriesView />}

      {view === 'products' && (
        <>
      <form className="crawl-panel" onSubmit={handleCrawl}>
        <div className="crawl-row">
          <input
            type="url"
            required
            placeholder="https://example-shop.com/category/..."
            value={crawlUrl}
            onChange={(e) => setCrawlUrl(e.target.value)}
          />
          <button className="btn" type="submit" disabled={crawling}>
            {crawling ? 'Crawling…' : 'Crawl'}
          </button>
        </div>
        <div className="crawl-options">
          <label>
            Max pages
            <input
              type="number"
              min="1"
              max="500"
              value={maxPages}
              onChange={(e) => setMaxPages(e.target.value)}
            />
          </label>
          <label>
            <input
              type="checkbox"
              checked={fetchDescriptions}
              onChange={(e) => setFetchDescriptions(e.target.checked)}
            />
            Fetch descriptions from product pages
          </label>
          <span>Re-crawling updates existing products instead of duplicating them.</span>
        </div>
        {crawling && <ProgressBar progress={crawlProgress} kind="crawl" />}
        {crawlStatus && (
          <div className={`crawl-status ${crawlStatus.type}`}>{crawlStatus.message}</div>
        )}
        {crawlNotes.length > 0 && (
          <ul className="crawl-notes">
            {crawlNotes.map((note, i) => (
              <li key={i}>{note}</li>
            ))}
          </ul>
        )}
      </form>

      <div className="filters">
        <input
          type="search"
          placeholder="Search product name…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <select value={category} onChange={(e) => setCategory(e.target.value)}>
          <option value="">All categories</option>
          {categories.map((c) => (
            <option key={c} value={c}>
              {c}
            </option>
          ))}
        </select>
        <select
          value={sourceHost}
          onChange={(e) => setSourceHost(e.target.value)}
          title="Filter by which site a product was crawled from"
        >
          <option value="">All sites</option>
          {sourceOptions.map((s) => (
            <option key={s} value={s}>
              {s}
            </option>
          ))}
        </select>
        <input
          className="price-field"
          type="number"
          placeholder="Min price"
          value={minPrice}
          onChange={(e) => setMinPrice(e.target.value)}
        />
        <input
          className="price-field"
          type="number"
          placeholder="Max price"
          value={maxPrice}
          onChange={(e) => setMaxPrice(e.target.value)}
        />
      </div>

      <div className="result-meta">
        {loading
          ? 'Loading…'
          : loadError
            ? `Failed to load products: ${loadError}`
            : `${total} product${total === 1 ? '' : 's'} in the catalog`}
      </div>

      {!loading && !loadError && items.length === 0 && (
        <div className="empty-state">
          No products yet — crawl a shop/category page above to get started.
        </div>
      )}

      <div className="product-grid">
        {items.map((product) => (
          <ProductCard key={product.id} product={product} />
        ))}
      </div>

      {totalPages > 1 && (
        <div className="pagination">
          <button
            className="btn secondary"
            disabled={page <= 1}
            onClick={() => setPage((p) => Math.max(1, p - 1))}
          >
            Previous
          </button>
          <span>
            Page {page} of {totalPages}
          </span>
          <button
            className="btn secondary"
            disabled={page >= totalPages}
            onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
          >
            Next
          </button>
        </div>
      )}
        </>
      )}
    </div>
  )
}
