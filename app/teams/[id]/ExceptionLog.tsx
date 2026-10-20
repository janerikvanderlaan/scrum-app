import { RULES, activeExceptions, countKinds, kindLabel, type LoggedException } from '@/src/rules';
import { plural } from './flags';

export function ExceptionLog({ sprint, log }: { sprint: number; log: readonly LoggedException[] }) {
  const kc = countKinds(activeExceptions(log)), resolved = log.filter(o => o.resolved).length;
  return (
    <aside className="log" aria-label="Exception log">
      <h2>Exception log · Sprint {sprint}</h2>
      {log.length ? (
        <>
          <p className="note">{plural(kc.guide, 'Guide rule override')} · {plural(kc.team, 'team agreement override')} · {plural(kc.warn, 'accepted warning')}{resolved ? ` · ${resolved} resolved` : ''}</p>
          <ul>
            {log.map((o, i) => (
              <li key={i} className={o.resolved ? `${o.kind} resolved` : o.kind}>
                <span><span className="mono">{o.rule}</span> · {kindLabel(o)}{o.resolved && <span className="tag tag-ok">Resolved</span>}</span>
                <b>{o.detail}</b>
                <q>{RULES[o.rule].text}</q>
                {o.reason && <span>Reason: {o.reason}</span>}
                <span className="note">{o.who} · {o.stage}{o.day ? ` · day ${o.day}` : ''} · {o.time}</span>
              </li>
            ))}
          </ul>
        </>
      ) : <p className="note">No exceptions in this Sprint. Every block you override or warning you accept lands here and goes to the Retrospective.</p>}
    </aside>
  );
}
