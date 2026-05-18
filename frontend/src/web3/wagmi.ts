import { http, createConfig } from "wagmi";
import { injected, walletConnect } from "wagmi/connectors";
import { optimismSepolia } from "wagmi/chains";

export const supportedChains = [optimismSepolia] as const;
const walletConnectProjectId = import.meta.env.VITE_WALLETCONNECT_PROJECT_ID;

export const wagmiConfig = createConfig({
  chains: supportedChains,
  connectors: [
    injected(),
    ...(walletConnectProjectId
      ? [
          walletConnect({
            projectId: walletConnectProjectId,
            showQrModal: true,
          }),
        ]
      : []),
  ],
  transports: {
    [optimismSepolia.id]: http(import.meta.env.VITE_OP_SEPOLIA_RPC_URL),
  },
});
