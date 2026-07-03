/** A registry placeholder for a component that's built and live in-app but not yet given a
 *  real showcase — the leaf exists so the catalog names everything that ships. */
export function StubLeaf({ name }: { name: string }): React.JSX.Element {
  return (
    <div className="ds-leaf">
      <section className="ds-section">
        <h2>{name}</h2>
        <p className="ds-swatch-hex">Built + live in-app — showcase pending.</p>
      </section>
    </div>
  )
}
