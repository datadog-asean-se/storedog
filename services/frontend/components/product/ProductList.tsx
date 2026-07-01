import Link from 'next/link'
import { useState, useEffect } from 'react'
import cn from 'clsx'
import { Layout } from '@components/common'
import ProductCard from '@components/product/ProductCard'
import { ProductCard as ProductCardV2 } from '@components/product/ProductCard/ProductCard-v2'
import { Container, Skeleton } from '@components/ui'
import rangeMap from '@lib/range-map'
import { useBooleanFlagValue, useNumberFlagValue } from '@openfeature/react-sdk'
import { datadogRum } from '@datadog/browser-rum'

import { Product } from '@customTypes/product'
import { Page } from '@customTypes/page'

interface Props {
  products: Product[]
  pages: Page[]
  taxons: any
  taxon?: any
  cardVersion?: 'v1' | 'v2'
}

export default function ProductList({
  products,
  pages,
  taxons,
  taxon,
  cardVersion,
}: Props) {
  // Datadog Feature Flag: 'product-card-frustration'
  // true  → broken thumbnail cards (v2) — drives RUM Frustration Signals
  // false → normal cards (v1, default / safe state)
  // The flag value from Datadog overrides the server-side cardVersion prop,
  // and is automatically recorded in every RUM session for variant analysis.
  // Datadog Feature Flag: 'product-card-frustration'
  // true  → broken thumbnail cards (v2) — drives RUM Frustration Signals
  // false → normal cards (v1, default / safe state)
  const frustrationFlagEnabled = useBooleanFlagValue('product-card-frustration', false)
  const resolvedCardVersion = frustrationFlagEnabled ? 'v2' : (cardVersion ?? 'v1')

  // Datadog Feature Flag: 'product-grid-columns' (NUMBER)
  // 3 → standard 3-column grid (default)
  // 4 → compact 4-column grid
  const gridColumns = useNumberFlagValue('product-grid-columns', 3)

  useEffect(() => {
    datadogRum.addFeatureFlagEvaluation('product-card-frustration', frustrationFlagEnabled)
    datadogRum.addFeatureFlagEvaluation('product-grid-columns', gridColumns)
  }, [frustrationFlagEnabled, gridColumns])

  // if products prop is still empty after 5 seconds, show not found message
  const [notFound, setNotFound] = useState(false)
  useEffect(() => {
    const timeout = setTimeout(() => {
      if (products.length === 0) {
        setNotFound(true)
      }
    }, 5000)
    return () => clearTimeout(timeout)
  }, [products])

  function renderTaxonsList(taxons: any) {
    return Object.keys(taxons).map((taxon) => {
      const item = taxons[taxon]
      if (!item) return null
      return (
        <li
          className={item.children?.length ? 'list-none' : 'list-disc'}
          key={item.id}
        >
          {item.children?.length ? (
            item.attributes?.name
          ) : (
            <Link href={`/taxonomies/${item.attributes?.permalink ?? ''}`}>
              {item.attributes?.name}
            </Link>
          )}
          {item.children?.length > 0 && (
            <ul className="ps-5 mt-2 space-y-1 list-disc list-inside">
              {renderTaxonsList(item.children)}
            </ul>
          )}
        </li>
      )
    })
  }

  const ProductCardComponent =
    resolvedCardVersion === 'v2' ? ProductCardV2 : ProductCard

  return (
    <Container>
      <div className="grid grid-cols-1 lg:grid-cols-12 gap-4 mt-3 mb-20">
        <div className="col-span-8 lg:col-span-2 order-1 lg:order-none">
          <ul
            id="taxons-list"
            className="space-y-4 text-gray-500 list-disc list-inside dark:text-gray-400"
          >
            {renderTaxonsList(taxons)}
          </ul>
        </div>
        {/* Products */}
        <div className="col-span-8 order-3 lg:order-none">
          <h2 className="mb-4 text-3xl font-bold">
            Products{' '}
            {taxon?.id ? (
              <span className="text-accent">in {taxon.attributes.name}</span>
            ) : null}
          </h2>
          {products?.length ? (
            <div
              className="grid gap-6 product-grid"
              style={{ gridTemplateColumns: `repeat(${gridColumns}, minmax(0, 1fr))` }}
            >
              {products.map((product: Product) => (
                <ProductCardComponent
                  variant="simple"
                  key={product.slug}
                  className="animated fadeIn"
                  product={product}
                  imgProps={{
                    width: 480,
                    height: 480,
                  }}
                />
              ))}
            </div>
          ) : notFound ? (
            <div className="">
              <p>No products found!</p>
            </div>
          ) : (
            <div className="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
              {rangeMap(12, (i) => (
                <Skeleton key={i}>
                  <div className="w-60 h-60" />
                </Skeleton>
              ))}
            </div>
          )}{' '}
        </div>

        <div className="col-span-8 lg:col-span-2 order-2 lg:order-none">
          {/* do nothing here for now */}
        </div>
      </div>
    </Container>
  )
}

ProductList.Layout = Layout
