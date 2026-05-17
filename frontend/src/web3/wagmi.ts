import { http, createConfig } from "wagmi";
import { injected, walletConnect } from "wagmi/connectors";
import { optimismSepolia } from "wagmi/chains";

export const supportedChains = [optimismSepolia] as const;

export const wagmiConfig = createConfig({
  chains: supportedChains,
  connectors: [
    injected(),
    walletConnect({
      projectId: import.meta.env.VITE_WALLETCONNECT_PROJECT_ID ?? "demo-project-id",
      showQrModal: true,
    }),
  ],
  transports: {
    [optimismSepolia.id]: http(import.meta.env.VITE_OP_SEPOLIA_RPC_URL),
  },
});