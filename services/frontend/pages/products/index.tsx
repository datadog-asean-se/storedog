import type { GetServerSidePropsContext } from 'next'
import { ProductList } from '@components/product'
import { Page } from '@customTypes/page'
import { Product } from '@customTypes/product'

// product-card-frustration is now evaluated client-side via Datadog Feature Flags
// (OpenFeature provider in _app.tsx). The cardVersion prop is intentionally omitted
// so ProductList falls back to its own flag-driven logic.
export async function getServerSideProps(context: GetServerSidePropsContext) {
  const baseUrl = process.env.NEXT_PUBLIC_FRONTEND_API_ROUTE
    ? `${process.env.NEXT_PUBLIC_FRONTEND_API_ROUTE}/api`
    : 'http://localhost:3000/api'

  const productsRaw = await fetch(`${baseUrl}/products`).then((res) =>
    res.json()
  )
  const products: Product[] = Array.isArray(productsRaw) ? productsRaw : []

  const pagesRaw = await fetch(`${baseUrl}/pages`).then((res) => res.json())
  const pages: Page[] = Array.isArray(pagesRaw) ? pagesRaw : []

  const taxons = await fetch(`${baseUrl}/taxonomies`).then((res) => res.json())

  return {
    props: {
      products,
      pages,
      taxons,
    },
  }
}

export default ProductList
