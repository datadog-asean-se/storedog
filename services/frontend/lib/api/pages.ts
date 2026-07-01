import fetch from 'node-fetch'
import { Page } from '@customTypes/page'

const SPREE_URL_SERVERSIDE = process.env.NEXT_PUBLIC_SPREE_API_HOST
  ? `${process.env.NEXT_PUBLIC_SPREE_API_HOST}/api/v2`
  : 'http://service-proxy/services/backend/api/v2'

export const getPages = async (options: any = {}): Promise<Page[] | any> => {
  try {
    const url = `${SPREE_URL_SERVERSIDE}/storefront/cms_pages`

    const res = await fetch(url, {
      method: 'GET',
      headers: {
        'Content-Type': 'application/json',
      },
    })

    if (!res.ok) {
      const body = await res.text().catch(() => '<unreadable>')
      throw new Error(`Spree ${res.status} ${res.statusText} — ${url} — ${body}`)
    }

    const pagesApi: any = await res.json()

    const pages: Page[] = pagesApi.data.map((page: any) => {
      const id = page.id
      const name = page.attributes.title
      const url = `/${page.attributes.slug || ''}`

      return {
        id,
        name,
        url,
      }
    })

    return pages
  } catch (error) {
    console.error('[getPages]', error)
    throw error
  }
}

export const getPage = async (slug: string): Promise<Page | any> => {
  try {
    const url = `${SPREE_URL_SERVERSIDE}/storefront/cms_pages/${slug}`

    const res = await fetch(url, {
      method: 'GET',
      headers: {
        'Content-Type': 'application/json',
      },
    })

    if (!res.ok) {
      const body = await res.text().catch(() => '<unreadable>')
      throw new Error(`Spree ${res.status} ${res.statusText} — ${url} — ${body}`)
    }

    const pagesApi: any = await res.json()

    const page: Page = {
      id: pagesApi.data.id,
      name: pagesApi.data.attributes.title,
      url: `/${pagesApi.data.attributes.slug || ''}`,
      content: pagesApi.data.attributes.content,
    }

    return page
  } catch (error) {
    console.error('[getPage]', error)
    throw error
  }
}
