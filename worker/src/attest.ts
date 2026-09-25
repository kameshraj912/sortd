export interface AttestInput {
  keyId: string;
  attestation: string;
  challenge: string;
  teamId: string;
  bundleId: string;
  allowDevelop: boolean;
  nowMs: number;
  roots: Uint8Array[];
}

export const APPLE_APP_ATTEST_ROOT_PEM = "";

export function pemToDer(_pem: string): Uint8Array {
  throw new Error("not implemented yet");
}

export interface Certificate {
  tbs: Uint8Array;
  subject: Uint8Array;
  issuer: Uint8Array;
  subjectCommonName: string;
}

export function parseCertificate(_der: Uint8Array): Certificate {
  throw new Error("not implemented yet");
}

export async function verifySignedBy(_child: Certificate, _parent: Certificate): Promise<boolean> {
  throw new Error("not implemented yet");
}

export async function verifyAttestation(_input: AttestInput): Promise<void> {
  throw new Error("not implemented yet");
}
