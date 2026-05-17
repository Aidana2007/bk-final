import { AlertTriangle, CheckCircle2, PlugZap, Wallet } from "lucide-react";
import { useAccount, useChainId, useConnect, useDisconnect, useSwitchChain } from "wagmi";
import { supportedChains } from "../web3/wagmi";

export function ConnectBar() {
  const { address, isConnected } = useAccount();
  const chainId = useChainId();
  const { connectors, connect, isPending } = useConnect();
  const { disconnect } = useDisconnect();
  const { switchChain } = useSwitchChain();

  const targetChain = supportedChains[0];
  const wrongNetwork = isConnected && chainId !== targetChain.id;
  const connector = connectors[0];

  return (
    <header className="topbar">
      <div>
        <span className="eyebrow">Game Economy</span>
        <h1>Items, Crafting, Loot, Governance</h1>
      </div>

      <div className="walletCluster">
        <span className={wrongNetwork ? "status bad" : "status good"}>
          {wrongNetwork ? <AlertTriangle size={16} /> : <CheckCircle2 size={16} />}
          {wrongNetwork ? "Wrong network" : targetChain.name}
        </span>

        {wrongNetwork && (
          <button type="button" onClick={() => switchChain({ chainId: targetChain.id })}>
            <PlugZap size={16} />
            Switch
          </button>
        )}

        {isConnected ? (
          <button type="button" onClick={() => disconnect()}>
            <Wallet size={16} />
            {address?.slice(0, 6)}...{address?.slice(-4)}
          </button>
        ) : (
          <button
            type="button"
            disabled={!connector || isPending}
            onClick={() => connector && connect({ connector })}
          >
            <Wallet size={16} />
            {isPending ? "Connecting" : "Connect"}
          </button>
        )}
      </div>
    </header>
  );
}