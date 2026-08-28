const BRAND_ASSETS = {
  horizontal: {
    src: '/brand/the-score-club-horizontal.webp',
    width: 1053,
    height: 372,
  },
  shield: {
    src: '/brand/the-score-club-shield.webp',
    width: 620,
    height: 635,
  },
  stacked: {
    src: '/brand/the-score-club-stacked.webp',
    width: 572,
    height: 688,
  },
} as const

type BrandImageProps = {
  variant: keyof typeof BRAND_ASSETS
  alt: string
  className?: string
}

function BrandImage({ variant, alt, className }: BrandImageProps) {
  const asset = BRAND_ASSETS[variant]

  return (
    <img
      className={className}
      src={asset.src}
      alt={alt}
      width={asset.width}
      height={asset.height}
      decoding="async"
    />
  )
}

export function HeaderLogo() {
  return (
    <picture className="app-logo-picture">
      <source
        media="(max-width: 429px)"
        srcSet={BRAND_ASSETS.shield.src}
        type="image/webp"
      />
      <img
        className="app-logo-image"
        src={BRAND_ASSETS.horizontal.src}
        alt="The Score Club"
        width={BRAND_ASSETS.horizontal.width}
        height={BRAND_ASSETS.horizontal.height}
        decoding="async"
      />
    </picture>
  )
}

export function AuthLogo() {
  return (
    <picture className="auth-logo">
      <source
        media="(max-width: 820px)"
        srcSet={BRAND_ASSETS.stacked.src}
        type="image/webp"
      />
      <img
        className="auth-logo-image"
        src={BRAND_ASSETS.horizontal.src}
        alt="The Score Club"
        width={BRAND_ASSETS.horizontal.width}
        height={BRAND_ASSETS.horizontal.height}
        decoding="async"
      />
    </picture>
  )
}

export function LoadingMark() {
  return <BrandImage variant="shield" alt="" className="loading-mark" />
}

export function LoadingSplashLogo() {
  return (
    <BrandImage variant="stacked" alt="" className="loading-logo-stacked" />
  )
}
