/**
 * Sample React Native App
 * https://github.com/facebook/react-native
 *
 * @format
 */

import React from 'react';
import type {PropsWithChildren} from 'react';
import {
  SafeAreaView,
  ScrollView,
  StatusBar,
  StyleSheet,
  Text,
  useColorScheme,
  View,
} from 'react-native';

import {Colors, Header} from 'react-native/Libraries/NewAppScreen';

import firebase from '@react-native-firebase/app';
import analytics from '@react-native-firebase/analytics';
import appCheck from '@react-native-firebase/app-check';
import auth from '@react-native-firebase/auth';
import messaging from '@react-native-firebase/messaging';
import remoteConfig from '@react-native-firebase/remote-config';

type SectionProps = PropsWithChildren<{
  title: string;
}>;

function Section({children, title}: SectionProps): JSX.Element {
  const isDarkMode = useColorScheme() === 'dark';
  return (
    <View style={styles.sectionContainer}>
      <Text
        style={[
          styles.sectionTitle,
          {
            color: isDarkMode ? Colors.white : Colors.black,
          },
        ]}>
        {title}
      </Text>
      <Text
        style={[
          styles.sectionDescription,
          {
            color: isDarkMode ? Colors.light : Colors.dark,
          },
        ]}>
        {children}
      </Text>
    </View>
  );
}

function App(): JSX.Element {
  const isDarkMode = useColorScheme() === 'dark';

  const backgroundStyle = {
    backgroundColor: isDarkMode ? Colors.darker : Colors.lighter,
  };

  const dynStyles = StyleSheet.create({
    colors: {
      color: isDarkMode ? Colors.white : Colors.black,
    },
  });

  return (
    <SafeAreaView style={backgroundStyle}>
      <StatusBar
        barStyle={isDarkMode ? 'light-content' : 'dark-content'}
        backgroundColor={backgroundStyle.backgroundColor}
      />
      <ScrollView
        contentInsetAdjustmentBehavior="automatic"
        style={backgroundStyle}>
        <View
          style={{
            backgroundColor: isDarkMode ? Colors.black : Colors.white,
            alignItems: 'center',
          }}>
          <Section title="RNFirebase Build Demo" />
          <Text />
          <Text style={dynStyles.colors}>JSI Executor: {global.__jsiExecutorDescription}</Text>
          <Text />
          <Text style={dynStyles.colors}>These firebase modules appear to be working:</Text>
          <Text />
          {firebase.apps.length && <Text style={dynStyles.colors}>app()</Text>}
          {analytics().native && <Text style={dynStyles.colors}>analytics()</Text>}
          {appCheck().native && <Text style={dynStyles.colors}>appCheck()</Text>}
          {auth().native && <Text style={dynStyles.colors}>auth()</Text>}
          {messaging().native && <Text style={dynStyles.colors}>messaging()</Text>}
          {remoteConfig().native && <Text style={dynStyles.colors}>remoteConfig()</Text>}
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  sectionContainer: {
    marginTop: 32,
    paddingHorizontal: 24,
  },
  sectionTitle: {
    fontSize: 24,
    fontWeight: '600',
  },
  sectionDescription: {
    marginTop: 8,
    fontSize: 18,
    fontWeight: '400',
  },
  highlight: {
    fontWeight: '700',
  },
});

export default App;
