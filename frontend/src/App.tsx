import { ConnectBar } from "./components/ConnectBar";
import { useGameActions } from "./hooks/useGameActions";

export function App() {
  const actions = useGameActions();

  return (
    <>
      <ConnectBar />
      <main className="appShell">
        <section>
          <h2>Dashboard</h2>
          <p>Game systems frontend is connected.</p>
        </section>

        <section>
          <h2>Contract actions</h2>
          <div className="actionGrid">
            <button type="button" disabled={actions.isWriting || actions.isPending} onClick={actions.approveCrafting}>
              Approve crafting
            </button>
            <button type="button" disabled={actions.isWriting || actions.isPending} onClick={() => actions.craft(1n)}>
              Craft recipe #1
            </button>
            <button type="button" disabled={actions.isWriting || actions.isPending} onClick={actions.requestLoot}>
              Request loot
            </button>
          </div>

          {actions.hash && <p className="muted">Tx: {actions.hash}</p>}
          {actions.isPending && <p className="muted">Waiting for confirmation...</p>}
          {actions.isConfirmed && <p className="success">Transaction confirmed.</p>}
          {actions.error && <p className="error">{actions.error}</p>}
        </section>
      </main>
    </>
  );
}