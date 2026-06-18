import { useEffect, useState } from 'react'

export function useHashRoute(defaultId: string): string {
  const [id, setId] = useState(defaultId)

  useEffect(() => {
    const onHashChange = () => {
      const hash = window.location.hash.slice(1)
      setId(hash || defaultId)
    }

    onHashChange()
    window.addEventListener('hashchange', onHashChange)
    return () => window.removeEventListener('hashchange', onHashChange)
  }, [defaultId])

  return id
}

export function setHashRoute(id: string) {
  window.location.hash = id
}
