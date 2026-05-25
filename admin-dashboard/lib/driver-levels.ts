export function driverLevelTitle(level = 1) {
  if (level >= 21) return "Icône Denkma";
  if (level >= 18) return "Maître du Réseau";
  if (level >= 15) return "Légende Teranga";
  if (level >= 12) return "Gaïndé";
  if (level >= 10) return "Kilifa";
  if (level >= 9) return "Jambaar";
  if (level >= 7) return "Borom Route";
  if (level >= 5) return "Nandité";
  if (level >= 4) return "Yaatu";
  if (level >= 3) return "Goorgorlu";
  if (level >= 2) return "Ndaw";
  return "Débutant";
}

export function driverLevelProgress(xp = 0) {
  const xpPerLevel = 100;
  const current = xp % xpPerLevel;
  return {
    current,
    target: xpPerLevel,
    percent: Math.round((current / xpPerLevel) * 100),
  };
}
