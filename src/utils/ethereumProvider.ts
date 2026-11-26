import { BrowserProvider } from "ethers";

export function getEthereumProvider(): BrowserProvider {
  if (!window.ethereum) {
    throw new Error("MetaMask est introuvable. Installez ou activez l'extension.");
  }
  return new BrowserProvider(window.ethereum);
}
