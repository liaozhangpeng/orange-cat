function Oval({ cx, cy, w, h, className }) {
  return <ellipse className={className} cx={cx} cy={cy} rx={w / 2} ry={h / 2} />;
}

function OrangeCat() {
  const hy = 122;
  return (
    <svg className="cat" viewBox="48 12 250 242" role="img" aria-label="一只橘猫">
      <g transform="translate(160, 240) scale(-1, -1)">
        <Oval cx={0} cy={-6} w={130} h={14} className="shadow" />

        <path className="tail" d="M-40 22 C-104 16 -106 62 -86 97" />
        <path className="tail-fur" d="M-40 22 C-104 16 -106 62 -86 97" />
        <Oval cx={-86} cy={97} w={14} h={14} className="tail-tip" />

        <Oval cx={0} cy={50} w={118} h={100} className="fur" />
        {[-1, 1].map((side) =>
          [66, 50, 34].map((y) => (
            <path key={`${side}-${y}`} className="stripe" d={`M${side * 54} ${y} L${side * 42} ${y + 3}`} />
          )),
        )}
        <Oval cx={0} cy={40} w={46} h={62} className="belly" />

        {[-1, 1].map((side) => (
          <g key={side}>
            <path
              className="ear"
              d={`M${side * 64} ${hy + 18} L${side * 54} ${hy + 84} L${side * 12} ${hy + 50} Z`}
            />
            <path
              className="ear-inner"
              d={`M${side * 52} ${hy + 34} L${side * 50} ${hy + 72} L${side * 27} ${hy + 50} Z`}
            />
          </g>
        ))}

        <Oval cx={0} cy={hy} w={144} h={112} className="fur" />
        <path className="stripe" d={`M-15 ${hy + 50} L-10 ${hy + 37}`} />
        <path className="stripe" d={`M0 ${hy + 54} L0 ${hy + 39}`} />
        <path className="stripe" d={`M15 ${hy + 50} L10 ${hy + 37}`} />

        {[-1, 1].map((side) => (
          <g key={side}>
            <Oval cx={side * 30} cy={hy + 4} w={17} h={23} className="eye" />
            <Oval cx={side * 30 + 3.5} cy={hy + 9} w={7} h={8} className="eye-light" />
            <Oval cx={side * 30 - 3.5} cy={hy - 1.5} w={3.5} h={3.5} className="eye-light" />
          </g>
        ))}
        <Oval cx={-48} cy={hy - 16} w={24} h={13} className="blush" />
        <Oval cx={48} cy={hy - 16} w={24} h={13} className="blush" />
        <path className="nose" d={`M-7 ${hy - 6} L7 ${hy - 6} L0 ${hy - 13} Z`} />
        <path
          className="mouth"
          d={`M0 ${hy - 13} L0 ${hy - 17} M-11 ${hy - 17} C-10 ${hy - 25} -1 ${hy - 25} 0 ${hy - 17} C1 ${hy - 25} 10 ${hy - 25} 11 ${hy - 17}`}
        />
        {[-1, 1].map((side) =>
          [
            [hy - 6, hy],
            [hy - 12, hy - 13],
            [hy - 18, hy - 26],
          ].map(([y0, y1]) => (
            <path key={`${side}-${y0}`} className="whisker" d={`M${side * 54} ${y0} L${side * 84} ${y1}`} />
          )),
        )}

        <path className="leg" d="M-28 44 L-22 8" />
        <path className="leg-fur" d="M-28 44 L-22 8" />
        <Oval cx={-28} cy={44} w={24} h={24} className="fur-cap" />
        <Oval cx={-22} cy={8} w={32} h={22} className="paw" />
        <path className="toe" d="M-27 0 L-27 6 M-17 0 L-17 6" />

        <path className="leg" d="M28 44 L22 8" />
        <path className="leg-fur" d="M28 44 L22 8" />
        <Oval cx={28} cy={44} w={24} h={24} className="fur-cap" />
        <Oval cx={22} cy={8} w={32} h={22} className="paw" />
        <path className="toe" d="M17 0 L17 6 M27 0 L27 6" />

        <g transform="translate(78 16)">
          <path className="thread" d="M10 -12 C18 -11 18 -23 30 -19 C33 -17 32 -15 30 -13" />
          <circle className="ball" r="16" />
          <ellipse className="ball-line" rx="16" ry="7" transform="rotate(30)" />
          <ellipse className="ball-line" rx="16" ry="7" transform="rotate(90)" />
          <ellipse className="ball-line" rx="16" ry="7" transform="rotate(150)" />
          <ellipse className="gloss" cx="-6" cy="6" rx="4" ry="2.2" />
        </g>
      </g>
    </svg>
  );
}

export default OrangeCat;
