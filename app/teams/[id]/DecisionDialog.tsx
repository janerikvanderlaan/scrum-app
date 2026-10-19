import Link from 'next/link';
import { MIN_REASON_LENGTH, RULES, kindFor, type Finding } from '@/src/rules';
import { decide } from './actions';
import { TIER_LABEL } from './flags';

export function DecisionDialog({ teamId, finding, fields, error }: { teamId: string; finding: Finding; fields: Record<string, string>; error?: string }) {
  const override = kindFor(finding.rule) === 'override';
  return (
    <div className="modal" role="dialog" aria-modal="true" aria-labelledby="dlg-title">
      <form action={decide.bind(null, teamId)} className="dialog">
        <span className="eyebrow">{finding.rule} · {TIER_LABEL[RULES[finding.rule].tier]}</span>
        <h2 id="dlg-title">{finding.detail}</h2>
        <q>{RULES[finding.rule].text}</q>
        {Object.entries({ ...fields, rule: finding.rule, target: finding.target, detail: finding.detail }).map(([k, v]) => <input key={k} type="hidden" name={k} value={v} />)}
        {override && (
          <>
            <label htmlFor="ov-reason">Why does the team need to go ahead anyway?</label>
            <textarea id="ov-reason" name="reason" required minLength={MIN_REASON_LENGTH} autoFocus
              placeholder="For example: our coach starts next month and takes the Scrum Master role." />
            {error === 'reason' && <p className="error">Give a reason of at least {MIN_REASON_LENGTH} characters.</p>}
          </>
        )}
        <div className="row end">
          <Link href={`/teams/${encodeURIComponent(teamId)}`} className="btn ghost" id="ov-cancel">Cancel</Link>
          <button className={override ? 'btn danger' : 'btn'} id="ov-go">{override ? 'Override and log' : 'Continue'}</button>
        </div>
      </form>
    </div>
  );
}
