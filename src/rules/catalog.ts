// Rule texts are quoted from the 2020 Scrum Guide by Ken Schwaber and Jeff Sutherland,
// licensed CC BY-SA 4.0. IDs refer to the research project's phase 1 traceability sheet.

/**
 * rule:     Guide rule. Blocks; an override needs a reason and marks the Sprint as not following Scrum.
 * guidance: Guide guidance. Warns; accepting is logged.
 * confirm:  Asks for a confirmation only; confirming is logged as a warning.
 * team:     The team's own agreement. Blocks like a rule, but an override doesn't count against Scrum.
 */
export type Tier = 'rule' | 'guidance' | 'confirm' | 'team';

export interface Rule {
  text: string;
  tier: Tier;
  /** What the rule means for the team in practice, in the app's own words (not Guide text). */
  explain?: string;
}

export const RULES = {
  'SG-063': { text: 'The Scrum Team consists of one Scrum Master, one Product Owner, and Developers.', tier: 'rule' },
  'SG-095': { text: 'The Product Owner is one person, not a committee.', tier: 'rule' },
  'SG-068': { text: 'The Scrum Team is small enough to remain nimble and large enough to complete significant work within a Sprint, typically 10 or fewer people.', tier: 'guidance' },
  'SG-194': { text: 'For the Product Backlog it is the Product Goal.', tier: 'rule' },
  'SG-240': { text: 'If it is not an organizational standard, the Scrum Team must create a Definition of Done appropriate for the product.', tier: 'rule' },
  'SG-200': { text: 'Product Backlog items that can be Done by the Scrum Team within one Sprint are deemed ready for selection in a Sprint Planning event.', tier: 'rule' },
  'SG-150': { text: 'The Sprint Goal must be finalized prior to the end of Sprint Planning.', tier: 'rule' },
  'SG-164': { text: 'To reduce complexity, it is held at the same time and place every working day of the Sprint.', tier: 'rule' },
  'SG-233': { text: 'Work cannot be considered part of an Increment unless it meets the Definition of Done.', tier: 'rule' },
  'SG-125': { text: 'They are fixed length events of one month or less to create consistency.', tier: 'rule' },
  'SG-121': { text: 'Failure to operate any events as prescribed results in lost opportunities to inspect and adapt.', tier: 'rule' },
  'SG-187': { text: 'The Sprint Retrospective concludes the Sprint.', tier: 'rule' },
  'SG-185': { text: 'The most impactful improvements are addressed as soon as possible.', tier: 'rule' },
  'SG-238': {
    text: 'Instead, it returns to the Product Backlog for future consideration.', tier: 'confirm',
    explain: 'The Product Owner and the team reconsider the story’s priority, size and value. They may decide not to finish the remaining work, to take it into a Sprint again with a new size (if work has already been done), or to deprioritize it for a later Sprint.',
  },
  'SG-216': { text: 'The Sprint Backlog is a plan by and for the Developers.', tier: 'rule' },
  'TEAM-01': { text: 'Developers start Sprint Backlog items from top to bottom, in the order a Developer confirmed at the start of the Sprint.', tier: 'team' },
  'TEAM-02': { text: 'Product Backlog items and improvements are written as user stories: “As a … I want to … so that …”.', tier: 'team' },
  'TEAM-03': { text: 'A Sprint starts only with sized user stories whose total stays within the team’s average velocity.', tier: 'team' },
} as const satisfies Record<string, Rule>;

export type RuleId = keyof typeof RULES;

export const isGuideRule = (id: RuleId): boolean => RULES[id].tier !== 'team';
