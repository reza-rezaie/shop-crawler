import { useCallback, useEffect, useMemo, useState } from 'react'
import './App.css'

const PAGE_SIZE = 24

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

function formatPrice(price, currency) {
  if (price === null || price === undefined) return 'Price unknown'
  const symbol = currency && currency.length <= 3 ? currency : ''
  return `${symbol}${price.toFixed(2)}${!symbol && currency ? ` ${currency}` : ''}`
}

function ProductCard({ product }) {
  return (
    <a
      className="product-card"
      href={product.product_url}
      target="_blank"
      rel="noreferrer"
    >
      <div className="product-thumb">
        {product.image_url ? (
          <img src={product.image_url} alt={product.name} loading="lazy" />
        ) : (
          <span className="placeholder">No image</span>
        )}
      </div>
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
  const [crawlUrl, setCrawlUrl] = useState('https://books.toscrape.com/')
  const [maxPages, setMaxPages] = useState(3)
  const [fetchDescriptions, setFetchDescriptions] = useState(true)
  const [crawling, setCrawling] = useState(false)
  const [crawlStatus, setCrawlStatus] = useState(null) // {type, message}
  const [crawlNotes, setCrawlNotes] = useState([])

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

  const loadProducts = useCallback(async () => {
    setLoading(true)
    setLoadError(null)
    try {
      const params = new URLSearchParams()
      if (search) params.set('search', search)
      if (category) params.set('category', category)
      if (sourceHost) params.set('source_host', sourceHost)
      if (minPrice) params.set('min_price', minPrice)
      if (maxPrice) params.set('max_price', maxPrice)
      params.set('page', String(page))
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
        await loadCategories()
        await loadSources()
        await loadProducts()
      }
    } catch (err) {
      setCrawlStatus({ type: 'error', message: err.message })
    } finally {
      setCrawling(false)
    }
  }

  const totalPages = useMemo(
    () => Math.max(1, Math.ceil(total / PAGE_SIZE)),
    [total],
  )

  return (
    <div className="app">
      <header className="app-header">
        <h1>Mojo Product Crawler</h1>
        <p className="subtitle">
          Native-Mojo crawler + SQLite catalog, browsable locally.
        </p>
      </header>

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
              max="20"
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
          {sources.map((s) => (
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
    </div>
  )
}
