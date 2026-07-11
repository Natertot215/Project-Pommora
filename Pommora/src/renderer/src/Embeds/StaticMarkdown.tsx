import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'

/** The at-rest markdown render every embed shares (E-4: one live editor per
 *  surface — everything else renders static through this). */
export function StaticMarkdown({ body }: { body: string }): React.JSX.Element | null {
  if (body.trim() === '') return null
  return <ReactMarkdown remarkPlugins={[remarkGfm]}>{body}</ReactMarkdown>
}
