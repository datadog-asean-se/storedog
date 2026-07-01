import '@assets/main.css'
import '@assets/chrome-bug.css'
import 'keen-slider/keen-slider.min.css'

import { FC, useEffect } from 'react'
import type { AppProps } from 'next/app'
import { CartProvider, useCart } from '@lib/CartContext'

import { Head } from '@components/common'
import { ManagedUIContext } from '@components/ui/context'
import { datadogRum } from '@datadog/browser-rum'
import ErrorBoundary from '@components/ErrorBoundary'
import { OpenFeatureProvider } from '@openfeature/react-sdk'
import { OpenFeature } from '@openfeature/web-sdk'
import { DatadogProvider } from '@datadog/openfeature-browser'

datadogRum.init({
  applicationId: `${
    process.env.NEXT_PUBLIC_DD_APPLICATION_ID || 'DD_APPLICATION_ID_PLACEHOLDER'
  }`,
  clientToken: `${
    process.env.NEXT_PUBLIC_DD_CLIENT_TOKEN || 'DD_CLIENT_TOKEN_PLACEHOLDER'
  }`,
  site: (process.env.NEXT_PUBLIC_DD_SITE || 'datadoghq.com') as
    | 'datadoghq.com'
    | 'datadoghq.eu'
    | 'us3.datadoghq.com'
    | 'us5.datadoghq.com'
    | 'ap1.datadoghq.com',
  service: `${process.env.NEXT_PUBLIC_DD_SERVICE_FRONTEND || 'store-frontend'}`,
  version: `${process.env.NEXT_PUBLIC_DD_VERSION_FRONTEND || '1.0.0'}`,
  env: `${process.env.NEXT_PUBLIC_DD_ENV || 'development'}`,
  trackUserInteractions: true,
  trackResources: true,
  trackLongTasks: true,
  sessionSampleRate: 100,
  sessionReplaySampleRate: 100,
  silentMultipleInit: true,
  defaultPrivacyLevel: 'mask-user-input',
  allowedTracingUrls: [
    {
      match: /https:\/\/.*\.env.play.instruqt\.com/,
      propagatorTypes: ['tracecontext', 'datadog', 'b3', 'b3multi'],
    },
    {
      match: /^http:\/\/localhost(:\d+)?$/,
      propagatorTypes: ['tracecontext', 'datadog', 'b3', 'b3multi'],
    },
    {
      match: /.*/,
      propagatorTypes: ['tracecontext', 'datadog', 'b3', 'b3multi'],
    },
  ],
  traceSampleRate: 100,
  allowUntrustedEvents: true,
  beforeSend: (event) => {
    if (
      event.type === 'error' &&
      event.error.message ===
        'The resource you were looking for could not be found.'
    ) {
      console.log(event)
      return false
    }
    return true
  },
})

// Initialise Datadog OpenFeature provider client-side only.
// env:'dev' targets the Datadog Feature Flag environment whose queries include "dev".
// enableRumFeatureFlagTracking  → adds @feature_flags.* attributes to every RUM session
// enableFlagEvaluationTracking  → powers the real-time Client Evaluations chart on the flag page
// targetingKey                  → required for % rollout to deterministically bucket users
if (typeof window !== 'undefined') {
  const ffProvider = new DatadogProvider({
    clientToken: `${process.env.NEXT_PUBLIC_DD_CLIENT_TOKEN || ''}`,
    applicationId: `${process.env.NEXT_PUBLIC_DD_APPLICATION_ID || ''}`,
    site: (process.env.NEXT_PUBLIC_DD_SITE || 'datadoghq.com') as any,
    env: 'dev',
    service: 'store-frontend',
    enableExposureLogging: true,
    enableFlagEvaluationTracking: true,
    enableRumFeatureFlagTracking: true,
  })
  // Use the RUM session ID as the targetingKey so the 50/50 allocation
  // deterministically buckets the same browser session into the same variant.
  const sessionId =
    datadogRum.getInternalContext?.()?.session_id ||
    Math.random().toString(36).slice(2)
  OpenFeature.setProviderAndWait(ffProvider, { targetingKey: sessionId })
    .catch((err) => console.warn('[FF] Provider init failed, using defaults:', err))
}

const Noop: FC = ({ children }) => <>{children}</>

const CartWatcher = () => {
  const { cart } = useCart()
  useEffect(() => {
    if (!cart) {
      return
    }

    datadogRum.setGlobalContextProperty('cart_status', {
      cartTotal: cart.totalPrice,
    })
  }, [cart])

  return null
}

export default function MyApp({ Component, pageProps }: AppProps) {
  const Layout = (Component as any).Layout || Noop

  useEffect(() => {
    document.body.classList?.remove('loading')
    if (window?.location.search.includes('end_session=true')) {
      datadogRum.stopSession()
    }
  }, [])

  return (
    <>
      <OpenFeatureProvider>
        <CartProvider>
          <Head />
          <ManagedUIContext>
            <CartWatcher />
            <Layout pageProps={pageProps}>
              <ErrorBoundary>
                <Component {...pageProps} />
              </ErrorBoundary>
            </Layout>
          </ManagedUIContext>
        </CartProvider>
      </OpenFeatureProvider>
    </>
  )
}
