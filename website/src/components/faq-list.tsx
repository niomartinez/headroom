import type { CSSProperties } from "react";
import type { FaqItem } from "@/content/faq";

export function FaqList({ items }: { items: FaqItem[] }) {
  return (
    <div className="faq-list border-t border-line">
      {items.map((item, index) => (
        <details key={item.question} className="faq-item" data-reveal style={{ "--d": `${Math.min(index, 4) * 50}ms` } as CSSProperties}>
          <summary>
            <span>{item.question}</span>
            <span className="plus" aria-hidden="true" />
          </summary>
          <div className="answer">
            {item.answer.map((paragraph) => (
              <p key={paragraph} className="[&+&]:mt-3">
                {paragraph}
              </p>
            ))}
          </div>
        </details>
      ))}
    </div>
  );
}
