import type { InferGetServerSidePropsType } from 'next'
import { useEffect } from 'react'
import { Layout } from '@components/common'
import Ad from '@components/common/Ad'
import { ProductCard } from '@components/product'
import { Grid, Marquee } from '@components/ui'
import { Product } from '@customTypes/product'
import { Page } from '@customTypes/page'
import { useStringFlagValue, useObjectFlagValue } from '@openfeature/react-sdk'
import { datadogRum } from '@datadog/browser-rum'

interface HeroStyle {
  bgColor: string
  textColor: string
  badge: string
}

const DEFAULT_PROMO = 'GET FREE SHIPPING WITH CODE SAGE'
const DEFAULT_HERO_STYLE: HeroStyle = { bgColor: '#632CA6', textColor: '#FFFFFF', badge: '' }

export async function getServerSideProps() {
  const baseUrl = process.env.NEXT_PUBLIC_FRONTEND_API_ROUTE
    ? `${process.env.NEXT_PUBLIC_FRONTEND_API_ROUTE}/api`
    : 'http://localhost:3000/api'

  let products: Product[] = await fetch(`${baseUrl}/products`)
    .then((res) => res.json())
    .catch((error) => {
      console.error(error)
      return []
    })

  // if products exists and is an array, reverse it
  if (products && Array.isArray(products)) {
    products.reverse()
  } else {
    products = []
  }

  const pages: Page[] = await fetch(`${baseUrl}/pages`)
    .then((res) => res.json())
    .catch((error) => {
      console.error(error)
      return []
    })

  const taxons = await fetch(`${baseUrl}/taxonomies`)
    .then((res) => res.json())
    .catch((error) => {
      console.error(error)
      return []
    })

  return {
    props: {
      products,
      pages,
      taxons,
    },
  }
}

export default function Home({
  products,
  pages,
  taxons,
}: InferGetServerSidePropsType<typeof getServerSideProps>) {
  console.log(pages)

  // Datadog Feature Flag: 'promo-banner-message' (STRING)
  // 'control'     → "GET FREE SHIPPING WITH CODE SAGE"
  // 'summer-sale' → "🔥 SUMMER SALE: 30% OFF EVERYTHING — USE CODE SUMMER30"
  const promoMessage = useStringFlagValue('promo-banner-message', DEFAULT_PROMO)

  // Datadog Feature Flag: 'homepage-hero-style' (JSON/OBJECT)
  // 'control' → Datadog purple (#632CA6), no badge
  // 'vibrant' → Orange (#FF6B35), "NEW" badge
  const heroStyle = useObjectFlagValue<HeroStyle>('homepage-hero-style', DEFAULT_HERO_STYLE)

  useEffect(() => {
    datadogRum.addFeatureFlagEvaluation('promo-banner-message', promoMessage)
    datadogRum.addFeatureFlagEvaluation('homepage-hero-style', JSON.stringify(heroStyle))
  }, [promoMessage, heroStyle])

  return (
    <>
      {/* ── Promo Banner — 'promo-banner-message' STRING feature flag ─────────── */}
      <div className="text-center py-2 px-4 text-sm font-semibold tracking-widest bg-black text-white">
        {promoMessage}
      </div>

      <Grid variant="filled">
        {products.slice(0, 6).map((product: any, i: number) => (
          <ProductCard
            key={product.id}
            product={product}
            imgProps={{
              width: i === 0 ? 1080 : 540,
              height: i === 0 ? 1080 : 540,
              priority: true,
            }}
          />
        ))}
      </Grid>

      <Ad />

      {/* ── Homepage Hero — 'homepage-hero-style' JSON feature flag ──────────── */}
      <div
        style={{ backgroundColor: heroStyle.bgColor, color: heroStyle.textColor }}
        className="border-b border-t border-accent-2 py-12"
      >
        <div className="max-w-8xl mx-auto px-6 flex flex-col gap-4">
          {heroStyle.badge && (
            <span
              className="inline-block text-xs font-bold uppercase tracking-wider px-3 py-1 rounded-full w-fit"
              style={{
                backgroundColor: heroStyle.textColor,
                color: heroStyle.bgColor,
              }}
            >
              {heroStyle.badge}
            </span>
          )}
          <h2 className="text-4xl font-bold leading-tight">
            The best gear, at the best prices.
          </h2>
          <p className="text-lg opacity-80 max-w-xl">
            Cupcake ipsum dolor sit amet lemon drops pastry cotton candy. Sweet
            carrot cake macaroon bonbon croissant fruitcake jujubes macaroon oat
            cake. Soufflé bonbon caramels jelly beans.
          </p>
        </div>
      </div>

      <Marquee>
        {products.map((product: any, i: number) => (
          <ProductCard key={product.id} product={product} variant="slim" />
        ))}
      </Marquee>
    </>
  )
}

Home.Layout = Layout
