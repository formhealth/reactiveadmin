import { Component, type ReactNode } from 'react'
import { reportClientError } from './reportClientError'

type Props = {
  where: string
  // A change re-arms a failed boundary, so navigating away from a broken page clears the error.
  resetKey?: string
  fallback: (reset: () => void) => ReactNode
  children: ReactNode
}

type State = { failed: boolean }

export class ErrorBoundary extends Component<Props, State> {
  state: State = { failed: false }

  static getDerivedStateFromError(): State {
    return { failed: true }
  }

  componentDidCatch(error: unknown) {
    reportClientError({ where: this.props.where, kind: 'render', message: error instanceof Error ? error.name : 'unknown' })
  }

  componentDidUpdate(prev: Props) {
    if (this.state.failed && prev.resetKey !== this.props.resetKey) this.reset()
  }

  reset = () => this.setState({ failed: false })

  render() {
    return this.state.failed ? this.props.fallback(this.reset) : this.props.children
  }
}
