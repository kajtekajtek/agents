# Reference Format

Use these patterns for citation consistency.

## Quick Mode Examples

- Inline link style:
  - `Route 53 health checks support endpoint monitoring and failover behavior ([AWS Docs](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/health-checks-how-route-53-chooses-records.html)).`
- Numeric style:
  - `Route 53 evaluates health check status before DNS response selection[1].`

## Formal Mode Template

```markdown
## Findings

- Claim A with supporting evidence[1]
- Claim B with supporting evidence[2]

## Further Reading

- Optional related source not directly cited

## References

- [AWS Route 53 health checks][1]
- [AWS Route 53 routing policies][2]

[1]: https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/health-checks-how-route-53-chooses-records.html
[2]: https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-policy.html
```

## Conflict Handling Example

```markdown
- Source A reports lower latency in region X[1].
- Source B reports no statistically significant difference[2].
- Interpretation: evidence is mixed; likely dependent on workload profile.
```

## Rules

- Prefer numeric references over inline links
- Do not place raw URLs directly in prose for formal mode.
- Do not duplicate the same source in both `## References` and `## Further Reading`.
- If one section relies on one source, cite at the end of the section or final bullet instead of every line.
