export function SectionHead({
  id,
  eyebrow,
  title,
  intro,
}: {
  id: string;
  eyebrow: string;
  title: string;
  intro?: string;
}) {
  return (
    <div className="grid gap-4 border-t border-line pt-8 sm:gap-6 sm:pt-14 short:pt-8 lg:grid-cols-[minmax(0,1.35fr)_minmax(0,1fr)] lg:items-end lg:gap-16">
      <div data-reveal>
        <p className="eyebrow">{eyebrow}</p>
        <h2 id={id} className="section-title mt-4 max-w-[16ch] sm:mt-5">
          {title}
        </h2>
      </div>
      {intro && (
        <p data-reveal className="lede max-w-[460px] lg:justify-self-end" style={{ "--d": "90ms" } as React.CSSProperties}>
          {intro}
        </p>
      )}
    </div>
  );
}
