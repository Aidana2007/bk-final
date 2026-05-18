import { useEffect, useMemo, useState } from "react";
import { Abi, Address, formatUnits, isAddress, parseUnits, zeroAddress } from "viem";
import { useAccount, useReadContract, useReadContracts } from "wagmi";
import { ArrowDownUp, Hammer, ShoppingCart, Sparkles, Vote } from "lucide-react";
import ammAbi from "./abi/AMM.json";
import gameItemsAbi from "./abi/GameItems.json";
import governorAbi from "./abi/Governor.json";
import { ConnectBar } from "./components/ConnectBar";
import { useGameActions } from "./hooks/useGameActions";
import { contracts, subgraphUrl } from "./web3/addresses";

type InventoryRow = { itemId: string; balance: string };
type RecipeRow = { id: string; outputItemId: string; outputAmount: string };
type LootRow = { id: string; fulfilled: boolean; itemId?: string; amount?: string };

const trackedItemIds = [1n, 2n, 3n, 4n, 5n, 10n];
const stateLabels = ["Pending", "Active", "Canceled", "Defeated", "Succeeded", "Queued", "Expired", "Executed"];

function shortAddress(value?: string) {
  return value && isAddress(value) ? `${value.slice(0, 6)}...${value.slice(-4)}` : "Not configured";
}

function configured(value: Address) {
  return value !== zeroAddress;
}

function useSubgraphDashboard(account?: Address) {
  const [inventory, setInventory] = useState<InventoryRow[]>([]);
  const [recipes, setRecipes] = useState<RecipeRow[]>([]);
  const [loot, setLoot] = useState<LootRow[]>([]);
  const [error, setError] = useState<string>();

  useEffect(() => {
    if (!subgraphUrl || !account) return;

    const controller = new AbortController();
    setError(undefined);

    fetch(subgraphUrl, {
      method: "POST",
      headers: { "content-type": "application/json" },
      signal: controller.signal,
      body: JSON.stringify({
        query: `query Dashboard($account: Bytes!) {
          itemBalances(where: { account: $account, balance_gt: 0 }, orderBy: itemId) {
            itemId
            balance
          }
          recipes(where: { active: true }, orderBy: id) {
            id
            outputItemId
            outputAmount
          }
          lootRequests(where: { player: $account }, orderBy: requestedAt, orderDirection: desc, first: 5) {
            id
            fulfilled
            itemId
            amount
          }
        }`,
        variables: { account: account.toLowerCase() },
      }),
    })
      .then((response) => response.json())
      .then((payload) => {
        if (payload.errors?.length) throw new Error(payload.errors[0].message);
        setInventory(payload.data?.itemBalances ?? []);
        setRecipes(payload.data?.recipes ?? []);
        setLoot(payload.data?.lootRequests ?? []);
      })
      .catch((reason) => {
        if (!controller.signal.aborted) setError(reason.message ?? "Subgraph request failed.");
      });

    return () => controller.abort();
  }, [account]);

  return { inventory, recipes, loot, error, enabled: Boolean(subgraphUrl) };
}

function ProposalRow({ proposalId, onVote }: { proposalId: bigint; onVote: (support: number) => void }) {
  const proposalState = useReadContract({
    address: contracts.governor,
    abi: governorAbi as Abi,
    functionName: "state",
    args: [proposalId],
    query: { enabled: configured(contracts.governor) },
  });
  const label = typeof proposalState.data === "number" ? stateLabels[proposalState.data] : "Unknown";

  return (
    <div className="tableRow">
      <span>#{proposalId.toString()}</span>
      <span>{label}</span>
      <div className="inlineActions">
        <button type="button" onClick={() => onVote(1)}>
          For
        </button>
        <button type="button" onClick={() => onVote(0)}>
          Against
        </button>
        <button type="button" onClick={() => onVote(2)}>
          Abstain
        </button>
      </div>
    </div>
  );
}

export function App() {
  const { address, isConnected } = useAccount();
  const actions = useGameActions();
  const graph = useSubgraphDashboard(address);
  const [recipeId, setRecipeId] = useState("1");
  const [proposalInput, setProposalInput] = useState("");
  const [proposalIds, setProposalIds] = useState<bigint[]>(() =>
    (import.meta.env.VITE_PROPOSAL_IDS ?? "")
      .split(",")
      .map((id: string) => id.trim())
      .filter(Boolean)
      .map(BigInt)
  );
  const [listingId, setListingId] = useState("");
  const [listingPrice, setListingPrice] = useState("");
  const [swapToken, setSwapToken] = useState<Address>(zeroAddress);
  const [swapAmount, setSwapAmount] = useState("");
  const [minOut, setMinOut] = useState("");

  const poolTokens = useReadContract({
    address: contracts.amm,
    abi: ammAbi as Abi,
    functionName: "poolTokens",
    query: { enabled: configured(contracts.amm) },
  });
  const reserves = useReadContract({
    address: contracts.amm,
    abi: ammAbi as Abi,
    functionName: "getReserves",
    query: { enabled: configured(contracts.amm) },
  });
  const onChainBalances = useReadContracts({
    contracts: trackedItemIds.map((id) => ({
      address: contracts.gameItems,
      abi: gameItemsAbi as Abi,
      functionName: "balanceOf",
      args: [address ?? zeroAddress, id],
    })),
    query: { enabled: isConnected && configured(contracts.gameItems) },
  });

  const [token0, token1] = useMemo(() => {
    const data = poolTokens.data as [Address, Address, Address] | undefined;
    return [data?.[0] ?? zeroAddress, data?.[1] ?? zeroAddress];
  }, [poolTokens.data]);
  const reserveData = reserves.data as [bigint, bigint, number] | undefined;
  const selectedSwapToken = swapToken === zeroAddress ? token0 : swapToken;
  const amountOut = useReadContract({
    address: contracts.amm,
    abi: ammAbi as Abi,
    functionName: "getAmountOut",
    args:
      swapAmount && reserveData
        ? [
            parseUnits(swapAmount, 18),
            selectedSwapToken === token0 ? reserveData[0] : reserveData[1],
            selectedSwapToken === token0 ? reserveData[1] : reserveData[0],
          ]
        : undefined,
    query: { enabled: Boolean(swapAmount && reserveData && configured(contracts.amm)) },
  });

  const handleAddProposal = () => {
    if (!proposalInput) return;
    const proposalId = BigInt(proposalInput);
    setProposalIds((current) => (current.includes(proposalId) ? current : [proposalId, ...current]));
    setProposalInput("");
  };

  return (
    <>
      <ConnectBar />
      <main className="appShell">
        <section className="overviewBand">
          <div>
            <span className="eyebrow">Protocol Console</span>
            <h2>GameFi economy operations</h2>
          </div>
          <div className="metricGrid">
            <div>
              <span>AMM</span>
              <strong>{shortAddress(contracts.amm)}</strong>
            </div>
            <div>
              <span>Governor</span>
              <strong>{shortAddress(contracts.governor)}</strong>
            </div>
            <div>
              <span>Subgraph</span>
              <strong>{graph.enabled ? "Connected" : "Not configured"}</strong>
            </div>
            <div>
              <span>Game items</span>
              <strong>{shortAddress(contracts.gameItems)}</strong>
            </div>
            <div>
              <span>Crafting</span>
              <strong>{shortAddress(contracts.craftingSystem)}</strong>
            </div>
            <div>
              <span>Loot drop</span>
              <strong>{shortAddress(contracts.lootDrop)}</strong>
            </div>
          </div>
        </section>

        <section className="panelGrid">
          <article className="panel">
            <h3>
              <Sparkles size={18} />
              Inventory
            </h3>
            <div className="table">
              {trackedItemIds.map((id, index) => (
                <div className="tableRow" key={id.toString()}>
                  <span>Item {id.toString()}</span>
                  <strong>{onChainBalances.data?.[index]?.result?.toString() ?? "0"}</strong>
                </div>
              ))}
            </div>
            {graph.inventory.length > 0 && (
              <div className="subtleList">
                {graph.inventory.map((item) => (
                  <span key={item.itemId}>#{item.itemId}: {item.balance}</span>
                ))}
              </div>
            )}
          </article>

          <article className="panel">
            <h3>
              <Hammer size={18} />
              Crafting and loot
            </h3>
            <label>
              Recipe
              <input value={recipeId} onChange={(event) => setRecipeId(event.target.value)} />
            </label>
            <div className="inlineActions">
              <button type="button" disabled={actions.isWriting} onClick={actions.approveCrafting}>
                Approve
              </button>
              <button type="button" disabled={actions.isWriting || !recipeId} onClick={() => actions.craft(BigInt(recipeId))}>
                Craft
              </button>
              <button type="button" disabled={actions.isWriting} onClick={actions.requestLoot}>
                Request loot
              </button>
            </div>
            <div className="subtleList">
              {graph.recipes.map((recipe) => (
                <span key={recipe.id}>Recipe {recipe.id}: {recipe.outputAmount} x item {recipe.outputItemId}</span>
              ))}
              {graph.loot.map((drop) => (
                <span key={drop.id}>Loot {drop.id}: {drop.fulfilled ? `${drop.amount} x item ${drop.itemId}` : "pending"}</span>
              ))}
            </div>
          </article>

          <article className="panel widePanel">
            <h3>
              <ArrowDownUp size={18} />
              AMM
            </h3>
            <div className="reserveGrid">
              <div>
                <span>{shortAddress(token0)}</span>
                <strong>{reserveData ? formatUnits(reserveData[0], 18) : "0"}</strong>
              </div>
              <div>
                <span>{shortAddress(token1)}</span>
                <strong>{reserveData ? formatUnits(reserveData[1], 18) : "0"}</strong>
              </div>
            </div>
            <div className="formGrid">
              <label>
                Token in
                <select value={selectedSwapToken} onChange={(event) => setSwapToken(event.target.value as Address)}>
                  <option value={token0}>{shortAddress(token0)}</option>
                  <option value={token1}>{shortAddress(token1)}</option>
                </select>
              </label>
              <label>
                Amount
                <input value={swapAmount} onChange={(event) => setSwapAmount(event.target.value)} />
              </label>
              <label>
                Minimum out
                <input value={minOut} onChange={(event) => setMinOut(event.target.value)} />
              </label>
            </div>
            <p className="muted">Quote: {amountOut.data ? formatUnits(amountOut.data as bigint, 18) : "0"}</p>
            <div className="inlineActions">
              <button type="button" disabled={!swapAmount} onClick={() => actions.approveTokenForAmm(selectedSwapToken, swapAmount)}>
                Approve
              </button>
              <button type="button" disabled={!swapAmount || !minOut} onClick={() => actions.swap(selectedSwapToken, swapAmount, minOut)}>
                Swap
              </button>
            </div>
          </article>

          <article className="panel">
            <h3>
              <Vote size={18} />
              Proposals
            </h3>
            <div className="formGrid compact">
              <input value={proposalInput} onChange={(event) => setProposalInput(event.target.value)} />
              <button type="button" onClick={handleAddProposal}>
                Track
              </button>
            </div>
            <div className="table">
              {proposalIds.map((proposalId) => (
                <ProposalRow key={proposalId.toString()} proposalId={proposalId} onVote={(support) => actions.vote(proposalId, support)} />
              ))}
              {proposalIds.length === 0 && <p className="muted">No proposals tracked.</p>}
            </div>
          </article>

          <article className="panel">
            <h3>
              <ShoppingCart size={18} />
              Marketplace
            </h3>
            <label>
              Listing
              <input value={listingId} onChange={(event) => setListingId(event.target.value)} />
            </label>
            <label>
              ETH
              <input value={listingPrice} onChange={(event) => setListingPrice(event.target.value)} />
            </label>
            <button type="button" disabled={!listingId || !listingPrice} onClick={() => actions.buyListing(BigInt(listingId), listingPrice)}>
              Buy
            </button>
          </article>
        </section>

        {(actions.hash || actions.error || graph.error) && (
          <section className="statusBand">
            {actions.hash && <span>Tx {shortAddress(actions.hash)}</span>}
            {actions.isPending && <span>Waiting for confirmation</span>}
            {actions.isConfirmed && <span className="success">Confirmed</span>}
            {actions.error && <span className="error">{actions.error}</span>}
            {graph.error && <span className="error">{graph.error}</span>}
          </section>
        )}
      </main>
    </>
  );
}
