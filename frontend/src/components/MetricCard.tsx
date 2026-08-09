type MetricCardProps = {
  label: string;
  value: string;
  detail?: string;
};

export default function MetricCard({ label, value, detail }: MetricCardProps) {
  return (
    <article className="metric-card">
      <p className="metric-label">{label}</p>
      <strong className="metric-value">{value}</strong>
      {detail && <p className="metric-detail">{detail}</p>}
    </article>
  );
}
