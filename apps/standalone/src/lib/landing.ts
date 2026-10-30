let landing: string | undefined

// A reload restores the key of the history entry it lands on, so no key value marks "the page this load opened with".
// The router's first location of this boot does.
export const trackLanding = ({ state }: { state: { location: { key: string } } }) => {
  landing = state.location.key
}

export const isLanding = (key: string) => key === landing
