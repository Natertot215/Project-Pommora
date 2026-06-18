import { GlassStage } from '../GlassStage'

/** Materials · Glass — the draggable glass panel over the stacked landscape surfaces. */
export function GlassLeaf(): React.JSX.Element {
  return (
    <div className="ds-leaf">
      <section className="ds-section">
        <h2>Materials · Glass</h2>
        <GlassStage />
      </section>
    </div>
  )
}
