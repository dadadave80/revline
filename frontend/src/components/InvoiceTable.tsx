import type { Address } from "viem";
import { formatUSDC } from "../format";

export type MerchantInvoice = {
  id: bigint;
  memo: string;
  amount: bigint;
  payer: Address;
  expiresAt: bigint;
  status: number;
};

const statusName = (invoice: MerchantInvoice) => {
  if (invoice.status === 1 && invoice.expiresAt !== 0n && invoice.expiresAt <= BigInt(Math.floor(Date.now() / 1000))) return "Expired";
  return ["Unknown", "Open", "Paid", "Cancelled"][invoice.status] ?? "Unknown";
};

const shortAddress = (address: Address) => `${address.slice(0, 6)}…${address.slice(-4)}`;

export default function InvoiceTable({ invoices }: { invoices: MerchantInvoice[] }) {
  return (
    <section className="invoice-section" aria-labelledby="invoices-heading">
      <div className="section-heading">
        <div><p className="eyebrow">Payment links</p><h2 id="invoices-heading">Invoices</h2></div>
        <span>{invoices.length} total</span>
      </div>
      {invoices.length === 0 ? <p className="empty-state">Create an invoice to start building verified revenue.</p> : (
        <div className="table-wrap">
          <table>
            <thead><tr><th>ID</th><th>Memo</th><th>Gross amount</th><th>Status</th><th>Payer</th><th /></tr></thead>
            <tbody>
              {invoices.map((invoice) => {
                const status = statusName(invoice);
                return <tr key={invoice.id.toString()}>
                  <td>#{invoice.id.toString()}</td>
                  <td>{invoice.memo || "—"}</td>
                  <td>{formatUSDC(invoice.amount)} USDC</td>
                  <td><span className={`status status-${status.toLowerCase()}`}>{status}</span></td>
                  <td>{invoice.payer === "0x0000000000000000000000000000000000000000" ? "—" : shortAddress(invoice.payer)}</td>
                  <td>{status === "Open" && <a href={`/#/pay/${invoice.id.toString()}`}>Pay link</a>}</td>
                </tr>;
              })}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}
