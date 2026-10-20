'use client';

import { useEffect, useRef, useState } from 'react';

/** A checkbox that ticks or clears every checkbox called `name` in its form, and shows whether all are ticked. */
export function CheckAll({ name, label }: { name: string; label: string }) {
  const ref = useRef<HTMLInputElement>(null);
  const [all, setAll] = useState(false);
  const boxes = () => [...(ref.current?.form?.querySelectorAll<HTMLInputElement>(`input[type="checkbox"][name="${name}"]`) ?? [])];

  useEffect(() => {
    const form = ref.current?.form;
    const sync = () => {
      const list = boxes(), ticked = list.filter(b => b.checked).length;
      setAll(list.length > 0 && ticked === list.length);
      if (ref.current) ref.current.indeterminate = ticked > 0 && ticked < list.length;
    };
    sync();
    form?.addEventListener('change', sync);
    return () => form?.removeEventListener('change', sync);
  });

  return (
    <label className="check check-all">
      <input ref={ref} type="checkbox" checked={all} onChange={e => {
        for (const b of boxes()) b.checked = e.currentTarget.checked;
        ref.current?.form?.dispatchEvent(new Event('change'));
      }} /> {label}
    </label>
  );
}
